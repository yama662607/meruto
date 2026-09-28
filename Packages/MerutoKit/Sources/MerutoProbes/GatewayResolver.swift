import Darwin
import MerutoCore

/// ルーティングテーブル (`sysctl NET_RT_FLAGS / RTF_GATEWAY`) から IPv4 の既定ゲートウェイを読む。
/// iOS SDK には `net/route.h` が無いので、使う定数と `rt_msghdr` の配置をここで持つ。
public enum GatewayResolver {
    // <net/route.h>
    private static let NET_RT_FLAGS: Int32 = 2
    private static let RTF_GATEWAY: Int32 = 0x2
    private static let RTA_DST: Int32 = 0x1
    private static let RTA_GATEWAY: Int32 = 0x2
    private static let RTAX_MAX = 8
    /// `struct rt_msghdr` の大きさ (固定部 36B + `struct rt_metrics` 56B)。
    private static let headerSize = 92
    private static let flagsOffset = 8
    private static let addrsOffset = 12
    private static let indexOffset = 4

    /// 既定ゲートウェイ (ホストバイトオーダー) と、その経路のインターフェイス名。
    public static func defaultGateway(preferring interface: String? = "en0") -> (address: UInt32, interface: String)? {
        let candidates = allDefaultGateways()
        if let interface, let match = candidates.first(where: { $0.interface == interface }) {
            return match
        }
        return candidates.first
    }

    /// 既定経路すべて (VPN や複数の物理 IF があると複数ある)。
    public static func allDefaultGateways() -> [(address: UInt32, interface: String)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_GATEWAY]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard buffer.withUnsafeMutableBytes({ sysctl(&mib, UInt32(mib.count), $0.baseAddress, &length, nil, 0) }) == 0
        else { return [] }

        var candidates: [(address: UInt32, interface: String)] = []
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + headerSize <= length {
                let messageLength = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard messageLength > 0 else { break }
                defer { offset += messageLength }
                let flags = raw.loadUnaligned(fromByteOffset: offset + flagsOffset, as: Int32.self)
                let addrs = raw.loadUnaligned(fromByteOffset: offset + addrsOffset, as: Int32.self)
                let index = raw.loadUnaligned(fromByteOffset: offset + indexOffset, as: UInt16.self)
                guard flags & RTF_GATEWAY != 0, addrs & RTA_DST != 0, addrs & RTA_GATEWAY != 0 else { continue }

                var cursor = offset + headerSize
                var destination: UInt32?
                var gateway: UInt32?
                for bit in 0..<RTAX_MAX where addrs & (1 << bit) != 0 {
                    guard cursor + 2 <= offset + messageLength else { break }
                    let saLength = Int(raw[cursor])
                    let family = Int32(raw[cursor + 1])
                    if family == AF_INET, saLength >= 8 {
                        let value = UInt32(raw[cursor + 4]) << 24 | UInt32(raw[cursor + 5]) << 16
                            | UInt32(raw[cursor + 6]) << 8 | UInt32(raw[cursor + 7])
                        if bit == 0 { destination = value }
                        if bit == 1 { gateway = value }
                    } else if bit == 0, saLength == 0 {
                        // 長さ 0 の宛先は 0.0.0.0 (既定経路) を表す。
                        destination = 0
                    }
                    // sockaddr は 4 バイト境界に揃えて並ぶ (長さ 0 も 4 バイト消費)。
                    cursor += saLength > 0 ? (saLength + 3) & ~3 : 4
                }
                guard destination == 0, let gateway, gateway != 0 else { continue }
                var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                let name = if_indextoname(UInt32(index), &nameBuffer) != nil
                    ? String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    : ""
                candidates.append((gateway, name))
            }
        }
        return candidates
    }
}
