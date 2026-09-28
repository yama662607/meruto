import Foundation
import MerutoCore
import Testing

@testable import MerutoProbes

/// 実機 (この Mac) の値を読むスモークテスト。値の中身ではなく「読めること」と妥当な範囲を確かめる。
@Suite struct ProbeSmokeTests {
    @Test func cpuSamplesAfterSecondRead() async throws {
        let probe = CPUProbe()
        #expect(probe.sample() == nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        let sample = try #require(probe.sample())
        #expect(!sample.cores.isEmpty)
        #expect((0...1).contains(sample.total.total))
    }

    @Test func memoryIsWithinPhysical() throws {
        let usage = try #require(MemoryProbe().sample())
        #expect(usage.total > 0)
        #expect(usage.used <= usage.total)
        #expect(usage.ownFootprint ?? 0 > 0)
    }

    @Test func networkRatesAreNonNegative() async throws {
        let probe = NetworkProbe()
        _ = probe.sample()
        try await Task.sleep(nanoseconds: 200_000_000)
        let sample = try #require(probe.sample())
        #expect(sample.wifi.download >= 0 && sample.wifi.upload >= 0)
    }

    @Test func storageAndSystemInfo() throws {
        let storage = try #require(StorageUsage.read())
        #expect(storage.total > storage.available)
        let info = SystemInfo.read()
        #expect(info.logicalCores > 0)
        #expect(info.bootDate != nil)
    }

    @Test func checksumMatchesKnownVector() {
        // RFC 1071 の例: 00 01 f2 03 f4 f5 f6 f7 → 和 0xddf2 → 補数 0x220d
        #expect(ICMPPinger.internetChecksum([0x00, 0x01, 0xf2, 0x03, 0xf4, 0xf5, 0xf6, 0xf7]) == 0x220d)
        let packet = ICMPPinger.makeEchoRequest(identifier: 0x1234, sequence: 7, payloadSize: 56)
        #expect(packet.count == 64)
        #expect(ICMPPinger.internetChecksum(packet) == 0)
    }

    @Test func replyParsingSkipsIPHeader() {
        var reply = [UInt8](repeating: 0, count: 28)
        reply[0] = 0x45  // IPv4, IHL 5
        reply[20] = 0  // echo reply
        reply[26] = 0
        reply[27] = 9
        #expect(ICMPPinger.isMatchingReply(reply, length: 28, sequence: 9))
        #expect(!ICMPPinger.isMatchingReply(reply, length: 28, sequence: 8))
    }

    /// ネットワーク環境に依存するので、ゲートウェイが見つかったときだけ ping まで確かめる。
    @Test func gatewayAndPing() async throws {
        guard let gateway = GatewayResolver.defaultGateway() else { return }
        #expect(gateway.address != 0)
        let pinger = ICMPPinger(interface: gateway.interface)
        var replies = 0
        for _ in 0..<3 {
            let result = await pinger.ping(host: gateway.address, timeout: 1)
            if let rtt = result.rtt {
                replies += 1
                #expect(rtt > 0 && rtt < 1)
            }
        }
        print("gateway \(ipv4String(gateway.address)) via \(gateway.interface): \(replies)/3 replies")
    }
}
