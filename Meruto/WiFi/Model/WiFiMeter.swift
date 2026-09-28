import CoreLocation
import Foundation
import MerutoCore
import MerutoProbes
import Network
import NetworkExtension

/// Wi-Fi のリンク品質をリアルタイムに測る。
///
/// 既定ゲートウェイ (= Wi-Fi ルーター) へ Wi-Fi インターフェイスに束縛した ICMP を約 6 回/秒打ち、
/// 小パケット 3 回に 1 回の割合で大パケットを混ぜる。統計は直近約 5 秒の窓で出し、
/// 針の動きは指数移動平均でならす (歩きながら見ても読めるように)。
@MainActor @Observable
final class WiFiMeter {
    enum State: Equatable {
        case idle
        case resolving
        case measuring
        case noWiFi
        case noGateway
    }

    private(set) var state: State = .idle
    private(set) var stats: LinkStats = .empty
    /// 表示用にならしたスコア (0...100)。
    private(set) var smoothedScore: Double?
    private(set) var scoreHistory = RingBuffer<Double>(capacity: 150)
    private(set) var rttHistory = RingBuffer<Double>(capacity: 150)
    private(set) var gateway: String?
    private(set) var localAddress: String?
    private(set) var ssid: String?
    private(set) var bssid: String?
    private(set) var packetsSent = 0
    private(set) var packetsLost = 0

    @ObservationIgnored private var analyzer = LinkQualityAnalyzer(window: 30)
    @ObservationIgnored private var pinger = ICMPPinger(interface: "en0")
    @ObservationIgnored private var pingerInterface = "en0"
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var infoLoop: Task<Void, Never>?
    @ObservationIgnored private let pathMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    @ObservationIgnored private var wifiAvailable = true
    @ObservationIgnored private let locationDelegate = LocationPermission()
    @ObservationIgnored private var users = 0
    /// 新しい値が出るたびに呼ぶ (DeviceMonitor のスナップショット更新用)。
    @ObservationIgnored var onSample: ((Double, TimeInterval?, String?) -> Void)?

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in self?.wifiAvailable = available }
        }
        pathMonitor.start(queue: DispatchQueue(label: "meruto.wifi.path"))
        locationDelegate.onChange = { [weak self] authorized in
            if authorized { Task { await self?.refreshNetworkInfo() } }
        }
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
            true
        #else
            false
        #endif
    }

    var grade: QualityGrade? { smoothedScore.map(QualityGrade.init(score:)) }

    /// Wi-Fi 画面と電波マップの両方が使うので、利用者の数で開始・停止する。
    func acquire() {
        users += 1
        if users == 1 { start() }
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 { stop() }
    }

    private func start() {
        guard loop == nil else { return }
        locationDelegate.request()
        loop = Task { [weak self] in await self?.run() }
        infoLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNetworkInfo()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func stop() {
        loop?.cancel()
        loop = nil
        infoLoop?.cancel()
        infoLoop = nil
        state = .idle
    }

    private func run() async {
        var target: UInt32?
        var counter = 0
        var lastResolve = Date.distantPast
        while !Task.isCancelled {
            // ゲートウェイは 10 秒ごと (と見失ったとき) に引き直す。ルーターが変わっても追従する。
            if target == nil || Date().timeIntervalSince(lastResolve) > 10 {
                if target == nil { state = .resolving }
                let resolved = Self.resolveTarget()
                lastResolve = Date()
                localAddress = resolved.local.map(ipv4String)
                if resolved.interface != pingerInterface {
                    pingerInterface = resolved.interface
                    pinger = ICMPPinger(interface: resolved.interface)
                }
                if resolved.gateway != target {
                    target = resolved.gateway
                    gateway = target.map(ipv4String)
                    analyzer.reset()
                }
            }
            guard Self.isSimulator || wifiAvailable, localAddress != nil else {
                state = .noWiFi
                smoothedScore = nil
                stats = .empty
                target = nil
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }
            guard let host = target else {
                state = .noGateway
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }
            state = .measuring

            counter += 1
            let large = counter % 4 == 0
            let result = await pinger.ping(
                host: host, payloadSize: large ? analyzer.largePayload : analyzer.smallPayload, timeout: 0.8)
            guard !Task.isCancelled else { break }
            ingest(result)
            // 応答が速いときも 1 周 ~160ms を保つ (約 6Hz)。
            if let rtt = result.rtt, rtt < 0.16 {
                try? await Task.sleep(nanoseconds: UInt64((0.16 - rtt) * 1e9))
            }
        }
    }

    private func ingest(_ result: PingResult) {
        analyzer.add(result)
        if result.payloadSize < analyzer.largePayload {
            packetsSent += 1
            if result.rtt == nil { packetsLost += 1 }
            rttHistory.append((result.rtt ?? 0.8) * 1000)
        }
        let newStats = analyzer.stats
        stats = newStats
        guard let score = newStats.score, newStats.sampleCount >= 3 else { return }
        let next = smoothedScore.map { $0 + 0.3 * (score - $0) } ?? score
        smoothedScore = next
        if result.payloadSize < analyzer.largePayload {
            scoreHistory.append(next)
        }
        onSample?(next, newStats.medianRTT, ssid)
    }

    private static func resolveTarget() -> (gateway: UInt32?, local: UInt32?, interface: String) {
        #if targetEnvironment(simulator)
            // シミュレータは Mac のネットワークをそのまま使うので、Mac の物理 IF (en*) の既定経路を測る。
            let routes = GatewayResolver.allDefaultGateways()
            if let route = routes.first(where: { $0.interface.hasPrefix("en") }) {
                let local = NetworkProbe.addresses().first { $0.name == route.interface }
                return (route.address, local?.address, route.interface)
            }
        #endif
        let wifi = NetworkProbe.addresses().first { $0.name == "en0" }
        if let route = GatewayResolver.defaultGateway(preferring: "en0"), route.interface == "en0" {
            return (route.address, wifi?.address, "en0")
        }
        // ルーティングテーブルから取れないとき (VPN が既定経路を持っている等) はサブネットから推定する。
        guard let wifi else { return (nil, nil, "en0") }
        return (guessedGateway(address: wifi.address, netmask: wifi.netmask), wifi.address, "en0")
    }

    private func refreshNetworkInfo() async {
        guard let network = await NEHotspotNetwork.fetchCurrent() else { return }
        ssid = network.ssid.isEmpty ? nil : network.ssid
        bssid = network.bssid.isEmpty ? nil : network.bssid
    }
}

/// SSID を読むために必要な位置情報の許可。
@MainActor
private final class LocationPermission: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onChange: ((Bool) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        onChange?(status == .authorizedWhenInUse || status == .authorizedAlways)
    }
}
