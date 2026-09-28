import Darwin
import Foundation
import MerutoCore

/// 非特権の ICMP ソケット (`SOCK_DGRAM` + `IPPROTO_ICMP`) で Echo を打つ。
/// Apple の SimplePing と同じ方式で、iOS のサンドボックス内から使える。
/// 1 つのソケットを専用のシリアルキューで使い回し、要求は 1 本ずつ順に処理する。
public final class ICMPPinger: @unchecked Sendable {
    private let queue = DispatchQueue(label: "meruto.icmp", qos: .userInitiated)
    private var socketFD: Int32 = -1
    private var sequence: UInt16 = 0
    private let identifier = UInt16.random(in: 1...UInt16.max)
    private var receiveBuffer = [UInt8](repeating: 0, count: 4096)
    private let boundInterface: String?

    /// `interface` を指定すると、そのインターフェイスから送る (`IP_BOUND_IF`)。
    /// VPN (Tailscale 等) が既定経路を握っていても Wi-Fi 区間を測れるようにするため。
    public init(interface: String? = nil) {
        boundInterface = interface
    }

    deinit {
        if socketFD >= 0 { close(socketFD) }
    }

    /// `host` (ホストバイトオーダー) へ Echo を 1 回送り、往復時間を返す。応答が無ければ nil。
    public func ping(host: UInt32, payloadSize: Int = 56, timeout: TimeInterval = 1.0) async -> PingResult {
        await withCheckedContinuation { continuation in
            queue.async {
                let rtt = self.performPing(host: host, payloadSize: payloadSize, timeout: timeout)
                continuation.resume(returning: PingResult(rtt: rtt, payloadSize: payloadSize))
            }
        }
    }

    private func openSocketIfNeeded() -> Bool {
        if socketFD >= 0 { return true }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return false }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        if let boundInterface {
            var index = UInt32(if_nametoindex(boundInterface))
            if index != 0 {
                setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, socklen_t(MemoryLayout<UInt32>.size))
            }
        }
        socketFD = fd
        return true
    }

    private func resetSocket() {
        if socketFD >= 0 { close(socketFD) }
        socketFD = -1
    }

    private func performPing(host: UInt32, payloadSize: Int, timeout: TimeInterval) -> TimeInterval? {
        guard openSocketIfNeeded() else { return nil }
        sequence &+= 1
        let seq = sequence
        let packet = Self.makeEchoRequest(identifier: identifier, sequence: seq, payloadSize: payloadSize)

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = host.bigEndian

        let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let sent = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketFD, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else {
            // 経路が変わった (Wi-Fi が切れた等) ときはソケットを作り直す。
            resetSocket()
            return nil
        }

        let deadline = start + UInt64(timeout * 1e9)
        while true {
            let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            guard now < deadline else { return nil }
            var fds = pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0)
            let waitMs = Int32(max(1, (deadline - now) / 1_000_000))
            let ready = poll(&fds, 1, waitMs)
            guard ready > 0 else { return nil }

            let received = receiveBuffer.withUnsafeMutableBytes { recv(socketFD, $0.baseAddress, $0.count, 0) }
            guard received > 0 else { continue }
            let end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            if Self.isMatchingReply(receiveBuffer, length: received, sequence: seq) {
                return Double(end - start) / 1e9
            }
            // 古い要求への遅れた応答などは読み捨てて待ち続ける。
        }
    }

    static func makeEchoRequest(identifier: UInt16, sequence: UInt16, payloadSize: Int) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 8 + max(0, payloadSize))
        packet[0] = 8  // ICMP_ECHO
        packet[1] = 0
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xff)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xff)
        for i in 8..<packet.count {
            packet[i] = UInt8(truncatingIfNeeded: i)
        }
        let checksum = internetChecksum(packet)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xff)
        return packet
    }

    /// RFC 1071。
    static func internetChecksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            sum &+= UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum &+= UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) &+ (sum >> 16) }
        return ~UInt16(sum)
    }

    /// Darwin の ICMP データグラムソケットは IP ヘッダ付きで返すので、あれば読み飛ばす。
    /// 識別子はカーネルが書き換えることがあるので、種別とシーケンス番号で照合する。
    static func isMatchingReply(_ buffer: [UInt8], length: Int, sequence: UInt16) -> Bool {
        var offset = 0
        if length >= 20, buffer[0] >> 4 == 4 {
            offset = Int(buffer[0] & 0x0f) * 4
        }
        guard length >= offset + 8 else { return false }
        let type = buffer[offset]
        let seq = UInt16(buffer[offset + 6]) << 8 | UInt16(buffer[offset + 7])
        return type == 0 && seq == sequence  // ICMP_ECHOREPLY
    }
}
