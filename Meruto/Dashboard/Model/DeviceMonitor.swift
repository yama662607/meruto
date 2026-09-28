import CoreTelephony
import Foundation
import Metal
import MerutoCore
import MerutoProbes
import Network
import QuartzCore
import UIKit
import WidgetKit

/// 端末の状態を 1 秒ごとに読む。画面に出ている間だけ動かす (`setActive`)。
@MainActor @Observable
final class DeviceMonitor {
    static let historyLength = 90

    // CPU
    private(set) var cpu: CPUSample?
    private(set) var cpuHistory = RingBuffer<Double>(capacity: historyLength)
    // メモリ
    private(set) var memory: MemoryUsage?
    // 通信
    private(set) var network: NetworkSample?
    private(set) var downloadHistory = RingBuffer<Double>(capacity: historyLength)
    private(set) var uploadHistory = RingBuffer<Double>(capacity: historyLength)
    private(set) var path: PathInfo = .unknown
    private(set) var internetLatency: TimeInterval?
    private(set) var latencyHistory = RingBuffer<Double>(capacity: 45)
    private(set) var addresses: [InterfaceAddress] = []
    private(set) var radioTechnology: String?
    // 電源・熱
    private(set) var batteryLevel: Double?
    private(set) var chargeState: ChargeState = .unknown
    private(set) var thermal: ThermalLevel = .nominal
    private(set) var lowPowerMode = false
    // ストレージ・システム
    private(set) var storage: StorageUsage?
    let system = SystemInfo.read()
    let gpu = GPUInfo.read()
    private(set) var displayFPS: Double = 0
    let maxFPS = UIScreen.main.maximumFramesPerSecond

    struct PathInfo: Equatable {
        var status: NWPath.Status?
        var interface: String
        var isExpensive: Bool
        var isConstrained: Bool

        static let unknown = PathInfo(status: nil, interface: "—", isExpensive: false, isConstrained: false)
    }

    @ObservationIgnored private let cpuProbe = CPUProbe()
    @ObservationIgnored private let memoryProbe = MemoryProbe()
    @ObservationIgnored private let networkProbe = NetworkProbe()
    @ObservationIgnored private let internetPinger = ICMPPinger()
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private let telephony = CTTelephonyNetworkInfo()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var latencyLoop: Task<Void, Never>?
    @ObservationIgnored private var fpsCounter: FPSCounter?
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Wi-Fi 画面から渡される最新のリンク品質 (ウィジェット用スナップショットに含める)。
    @ObservationIgnored var latestWiFi: (score: Double, rtt: TimeInterval?, ssid: String?, at: Date)?

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let info = PathInfo(
                status: path.status,
                interface: Self.interfaceName(path),
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained)
            Task { @MainActor in self?.path = info }
        }
        pathMonitor.start(queue: DispatchQueue(label: "meruto.path"))
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.persistSnapshot(reloadWidgets: true) }
            })
        readSlowValues()
    }

    func setActive(_ active: Bool) {
        if active {
            guard loop == nil else { return }
            fpsCounter = FPSCounter { [weak self] fps in self?.displayFPS = fps }
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    self?.sampleOnce()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            latencyLoop = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.measureLatency()
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        } else {
            loop?.cancel()
            loop = nil
            latencyLoop?.cancel()
            latencyLoop = nil
            fpsCounter?.invalidate()
            fpsCounter = nil
        }
    }

    private func sampleOnce() {
        tick += 1
        if let sample = cpuProbe.sample() {
            cpu = sample
            cpuHistory.append(sample.total.total)
        }
        if let mem = memoryProbe.sample() {
            memory = mem
        }
        if let net = networkProbe.sample() {
            network = net
            downloadHistory.append(net.combined.download)
            uploadHistory.append(net.combined.upload)
        }
        readPower()

        if tick % 5 == 1 { readSlowValues() }
        if tick % 30 == 1 { persistSnapshot(reloadWidgets: false) }
    }

    /// 1.1.1.1 への ICMP でインターネットまでの往復時間を測る。
    private func measureLatency() async {
        let result = await internetPinger.ping(host: 0x0101_0101, payloadSize: 56, timeout: 1.5)
        internetLatency = result.rtt
        latencyHistory.append((result.rtt ?? 1.5) * 1000)
    }

    private func readPower() {
        let device = UIDevice.current
        batteryLevel = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        chargeState =
            switch device.batteryState {
            case .unplugged: .unplugged
            case .charging: .charging
            case .full: .full
            default: .unknown
            }
        thermal = ThermalLevel(ProcessInfo.processInfo.thermalState)
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func readSlowValues() {
        storage = StorageUsage.read()
        addresses = NetworkProbe.addresses()
        radioTechnology = telephony.serviceCurrentRadioAccessTechnology?.values.first.map(Self.radioName)
        readPower()
    }

    func persistSnapshot(reloadWidgets: Bool) {
        let snapshot = DeviceSnapshot(
            timestamp: Date(),
            cpu: cpu?.total.total,
            memoryUsed: memory?.used,
            memoryTotal: memory?.total,
            storageUsed: storage?.used,
            storageTotal: storage?.total,
            batteryLevel: batteryLevel,
            chargeState: chargeState,
            thermal: thermal,
            lowPowerMode: lowPowerMode,
            download: network?.combined.download,
            upload: network?.combined.upload,
            wifiScore: latestWiFi?.score,
            wifiRTT: latestWiFi?.rtt,
            wifiSSID: latestWiFi?.ssid,
            wifiMeasuredAt: latestWiFi?.at)
        SharedContainer.writeJSON(snapshot, to: SharedContainer.File.deviceSnapshot)
        if reloadWidgets { WidgetCenter.shared.reloadAllTimelines() }
    }

    nonisolated private static func interfaceName(_ path: NWPath) -> String {
        guard path.status == .satisfied else { return "オフライン" }
        if path.usesInterfaceType(.wifi) { return "Wi-Fi" }
        if path.usesInterfaceType(.cellular) { return "モバイル通信" }
        if path.usesInterfaceType(.wiredEthernet) { return "有線" }
        return "その他"
    }

    nonisolated private static func radioName(_ technology: String) -> String {
        switch technology {
        case CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA: "5G"
        case CTRadioAccessTechnologyLTE: "LTE"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA: "3G"
        case CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS: "2G"
        default: technology.replacingOccurrences(of: "CTRadioAccessTechnology", with: "")
        }
    }
}
