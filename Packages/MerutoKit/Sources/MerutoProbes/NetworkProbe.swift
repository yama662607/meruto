import Darwin
import Foundation
import MerutoCore

/// インターフェイスの IPv4 情報。
public struct InterfaceAddress: Sendable, Equatable {
    public var name: String
    public var kind: InterfaceKind
    /// ホストバイトオーダー。
    public var address: UInt32
    public var netmask: UInt32

    public var addressString: String { ipv4String(address) }
}

/// Wi-Fi / モバイル通信それぞれの送受信速度。
public struct NetworkSample: Sendable, Equatable {
    public var wifi: NetworkRate
    public var cellular: NetworkRate
    public var totalSent: UInt64
    public var totalReceived: UInt64

    public var combined: NetworkRate {
        NetworkRate(upload: wifi.upload + cellular.upload, download: wifi.download + cellular.download)
    }
}

/// `getifaddrs` の `AF_LINK` エントリの `if_data` で送受信量を数える。
/// iOS では `NET_RT_IFLIST2` の 64bit カウンタが使えない環境があるので 32bit を使い、
/// 一周は `WrappingCounter32` で吸収する。
public final class NetworkProbe: @unchecked Sendable {
    private struct Key: Hashable {
        var name: String
        var direction: Int
    }

    private var counters: [Key: WrappingCounter32] = [:]
    private var lastTime: UInt64?
    private var sessionSent: UInt64 = 0
    private var sessionReceived: UInt64 = 0

    public init() {}

    public func sample() -> NetworkSample? {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        var deltas: [InterfaceKind: (sent: UInt64, received: UInt64)] = [:]

        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                let data = entry.pointee.ifa_data
            else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard let kind = InterfaceKind.classify(name), kind != .other else { continue }
            let ifData = data.assumingMemoryBound(to: if_data.self).pointee
            let ds = counters[Key(name: name, direction: 0), default: WrappingCounter32()].ingest(ifData.ifi_obytes)
            let dr = counters[Key(name: name, direction: 1), default: WrappingCounter32()].ingest(ifData.ifi_ibytes)
            deltas[kind, default: (0, 0)].sent &+= ds
            deltas[kind, default: (0, 0)].received &+= dr
        }

        defer { lastTime = now }
        guard let lastTime else { return nil }
        let seconds = Double(now - lastTime) / 1e9
        guard seconds > 0 else { return nil }

        func rate(_ kind: InterfaceKind) -> NetworkRate {
            let d = deltas[kind] ?? (0, 0)
            return NetworkRate(upload: Double(d.sent) / seconds, download: Double(d.received) / seconds)
        }
        for d in deltas.values {
            sessionSent &+= d.sent
            sessionReceived &+= d.received
        }
        return NetworkSample(
            wifi: rate(.wifi), cellular: rate(.cellular), totalSent: sessionSent, totalReceived: sessionReceived)
    }

    /// 稼働中の IPv4 アドレス一覧。
    public static func addresses() -> [InterfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var result: [InterfaceAddress] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                let mask = entry.pointee.ifa_netmask
            else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard let kind = InterfaceKind.classify(name) else { continue }
            let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            result.append(InterfaceAddress(name: name, kind: kind, address: address, netmask: netmask))
        }
        return result
    }
}
