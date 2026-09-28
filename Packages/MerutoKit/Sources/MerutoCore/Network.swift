/// iOS のインターフェイス種別。`en0` が Wi-Fi、`pdp_ip*` がモバイル通信。
public enum InterfaceKind: String, Sendable, Codable {
    case wifi
    case cellular
    case other

    public static func classify(_ name: String) -> InterfaceKind? {
        // 仮想・トンネル・ループバックは除く (VPN の utun を含めると物理 IF と二重計上になる)。
        let excluded = ["lo", "utun", "awdl", "llw", "bridge", "ap", "anpi", "gif", "stf", "ipsec", "XHC", "rmnet"]
        if excluded.contains(where: { name.hasPrefix($0) }) { return nil }
        if name == "en0" { return .wifi }
        if name.hasPrefix("pdp_ip") { return .cellular }
        if name.hasPrefix("en") { return .other }
        return nil
    }
}

/// 種別ごとの累積送受信バイト数。
public struct ByteCounters: Sendable, Equatable {
    public var sent: UInt64
    public var received: UInt64

    public init(sent: UInt64, received: UInt64) {
        self.sent = sent
        self.received = received
    }
}

/// 送受信の速度 (bytes/s)。
public struct NetworkRate: Sendable, Equatable, Codable {
    public var upload: Double
    public var download: Double

    public init(upload: Double, download: Double) {
        self.upload = upload
        self.download = download
    }

    public static let zero = NetworkRate(upload: 0, download: 0)
}

/// `getifaddrs` の `if_data` は 32bit で 4GB ごとに一周する。前回値との差を `&-` で取り、
/// 一周を跨いでも正しい増分を 64bit に積み上げる。
public struct WrappingCounter32: Sendable, Equatable {
    public private(set) var total: UInt64 = 0
    private var last: UInt32?

    public init() {}

    /// 新しい 32bit 値を取り込み、今回の増分を返す (初回は 0)。
    @discardableResult
    public mutating func ingest(_ value: UInt32) -> UInt64 {
        defer { last = value }
        guard let last else { return 0 }
        let delta = UInt64(value &- last)
        total &+= delta
        return delta
    }
}

extension NetworkRate {
    /// 2点間の速度。インターフェイスの増減などでカウンタが減ったときは 0 とみなす。
    public static func rate(from old: ByteCounters, to new: ByteCounters, seconds: Double) -> NetworkRate? {
        guard seconds > 0 else { return nil }
        let sent = new.sent >= old.sent ? new.sent - old.sent : 0
        let received = new.received >= old.received ? new.received - old.received : 0
        return NetworkRate(upload: Double(sent) / seconds, download: Double(received) / seconds)
    }
}

/// IPv4 アドレスとネットマスクから、既定ゲートウェイの候補 (サブネットの先頭 +1) を推定する。
/// ルーティングテーブルが読めないときの予備。
public func guessedGateway(address: UInt32, netmask: UInt32) -> UInt32? {
    guard netmask != 0, netmask != .max else { return nil }
    let candidate = (address & netmask) | 1
    return candidate == address ? nil : candidate
}

/// ホストバイトオーダーの IPv4 を "a.b.c.d" にする。
public func ipv4String(_ value: UInt32) -> String {
    "\(value >> 24 & 0xff).\(value >> 16 & 0xff).\(value >> 8 & 0xff).\(value & 0xff)"
}

/// "a.b.c.d" をホストバイトオーダーの IPv4 にする。
public func parseIPv4(_ text: String) -> UInt32? {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }
    var value: UInt32 = 0
    for part in parts {
        guard let byte = UInt8(part) else { return nil }
        value = value << 8 | UInt32(byte)
    }
    return value
}
