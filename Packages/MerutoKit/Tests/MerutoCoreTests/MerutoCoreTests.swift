import Foundation
import Testing

@testable import MerutoCore

@Suite struct CounterTests {
    @Test func wrappingCounterSurvivesOverflow() {
        var counter = WrappingCounter32()
        #expect(counter.ingest(UInt32.max - 10) == 0)
        #expect(counter.ingest(5) == 16)
        #expect(counter.ingest(105) == 100)
        #expect(counter.total == 116)
    }

    @Test func cpuUsageHandlesTickWraparound() throws {
        let old = CPUTicks(user: .max - 9, system: 0, idle: 0, nice: 0)
        let new = CPUTicks(user: 10, system: 0, idle: 20, nice: 0)
        let usage = try #require(CPUTicks.usage(from: old, to: new))
        #expect(abs(usage.total - 0.5) < 0.0001)
    }

    @Test func interfaceClassification() {
        #expect(InterfaceKind.classify("en0") == .wifi)
        #expect(InterfaceKind.classify("pdp_ip0") == .cellular)
        #expect(InterfaceKind.classify("utun3") == nil)
        #expect(InterfaceKind.classify("lo0") == nil)
        #expect(InterfaceKind.classify("awdl0") == nil)
    }

    @Test func ipv4RoundTripAndGatewayGuess() throws {
        let address = try #require(parseIPv4("192.168.1.23"))
        let mask = try #require(parseIPv4("255.255.255.0"))
        #expect(ipv4String(address) == "192.168.1.23")
        #expect(guessedGateway(address: address, netmask: mask).map(ipv4String) == "192.168.1.1")
        #expect(parseIPv4("300.1.1.1") == nil)
    }
}

@Suite struct FormattingTests {
    @Test func bytes() {
        #expect(Format.bytes(512.0) == "512 B")
        #expect(Format.bytes(1536.0) == "1.5 KB")
        #expect(Format.bytes(8.0 * 1024 * 1024 * 1024) == "8.0 GB")
        #expect(Format.bytes(256.0 * 1024 * 1024 * 1024) == "256 GB")
    }

    @Test func bitRateAndMilliseconds() {
        #expect(Format.bitRate(bitsPerSecond: 12_300_000) == "12 Mbps")
        #expect(Format.bitRate(bitsPerSecond: 1_500_000_000) == "1.5 Gbps")
        #expect(Format.milliseconds(0.0032) == "3.2 ms")
        #expect(Format.milliseconds(0.120) == "120 ms")
    }
}

@Suite struct LinkQualityTests {
    @Test func strongLinkScoresHigh() {
        let score = LinkQuality.score(rtt: 0.002, jitter: 0.0004, loss: 0)
        #expect(score > 95)
    }

    @Test func weakLinkScoresLow() {
        let score = LinkQuality.score(rtt: 0.080, jitter: 0.030, loss: 0.1)
        #expect(score < 35)
    }

    @Test func scoreIsMonotonicInRTT() {
        let a = LinkQuality.score(rtt: 0.004, jitter: 0.001, loss: 0)
        let b = LinkQuality.score(rtt: 0.020, jitter: 0.001, loss: 0)
        let c = LinkQuality.score(rtt: 0.100, jitter: 0.001, loss: 0)
        #expect(a > b && b > c)
    }

    @Test func totalLossIsZero() {
        #expect(LinkQuality.score(rtt: 0.002, jitter: 0, loss: 1) < 30)
        var analyzer = LinkQualityAnalyzer()
        for _ in 0..<5 { analyzer.add(PingResult(rtt: nil, payloadSize: 56)) }
        #expect(analyzer.stats.score == 0)
        #expect(analyzer.stats.loss == 1)
    }

    @Test func analyzerComputesMedianJitterAndRate() throws {
        var analyzer = LinkQualityAnalyzer(smallPayload: 56, largePayload: 1400, window: 10)
        for rtt in [0.002, 0.003, 0.002, 0.004, 0.002, 0.003] {
            analyzer.add(PingResult(rtt: rtt, payloadSize: 56))
        }
        // 大パケットは 1ms 長い → 2 * 1344 B * 8 / 1ms ≈ 21.5 Mbps
        for rtt in [0.0035, 0.0035, 0.0035, 0.0035] {
            analyzer.add(PingResult(rtt: rtt, payloadSize: 1400))
        }
        let stats = analyzer.stats
        #expect(stats.medianRTT == 0.0025)
        #expect(stats.sampleCount == 6)
        let jitter = try #require(stats.jitter)
        #expect(abs(jitter - 0.0014) < 0.00001)
        let rate = try #require(stats.estimatedRate)
        #expect(abs(rate - 21_504_000) < 1_000)
    }

    @Test func gradeBoundaries() {
        #expect(QualityGrade(score: 85) == .excellent)
        #expect(QualityGrade(score: 60) == .good)
        #expect(QualityGrade(score: 45) == .fair)
        #expect(QualityGrade(score: 20) == .weak)
        #expect(QualityGrade(score: 5) == .poor)
    }

    @Test func colorRampEndpoints() {
        #expect(QualityColor.rgb(for: 0) == QualityColor.stops[0].1)
        #expect(QualityColor.rgb(for: 100) == QualityColor.stops[4].1)
        #expect(QualityColor.rgb(for: 150) == QualityColor.stops[4].1)
    }
}

@Suite struct SurveyTests {
    @Test func heatmapInterpolatesBetweenPoints() {
        let points = [
            SurveyPoint(x: 0, y: 0, score: 100, rtt: nil, jitter: nil, loss: 0),
            SurveyPoint(x: 2, y: 0, score: 0, rtt: nil, jitter: nil, loss: 0),
        ]
        let bounds = SurveyBounds(minX: -0.5, maxX: 2.5, minY: -0.5, maxY: 0.5)
        let map = HeatmapBuilder.build(points: points, bounds: bounds, columns: 3, rows: 1)
        #expect(map.value(column: 0, row: 0) > 90)
        #expect(abs(map.value(column: 1, row: 0) - 50) < 0.001)
        #expect(map.value(column: 2, row: 0) < 10)
        #expect(map.opacity(column: 1, row: 0) > 0.9)
    }

    @Test func heatmapFadesFarFromSamples() {
        let points = [SurveyPoint(x: 0, y: 0, score: 80, rtt: nil, jitter: nil, loss: 0)]
        let bounds = SurveyBounds(minX: 0, maxX: 10, minY: 0, maxY: 10)
        let map = HeatmapBuilder.build(points: points, bounds: bounds, columns: 10, rows: 10)
        // 行 9 が y≈0.5 (手前)、列 0 が x≈0.5
        #expect(map.opacity(column: 0, row: 9) == 1)
        #expect(map.opacity(column: 9, row: 0) == 0)
    }

    @Test func boundsEncloseWithMinimumSpan() {
        let b = SurveyBounds.enclosing([(0, 0), (1, 0.5)], padding: 0.5, minimumSpan: 4)
        #expect(b.width == 4)
        #expect(b.height == 4)
        #expect(abs((b.minX + b.maxX) / 2 - 0.5) < 0.0001)
    }

    @Test func boundsFitAspect() {
        let b = SurveyBounds(minX: 0, maxX: 4, minY: 0, maxY: 4).fitted(toAspect: 2)
        #expect(b.width == 8)
        #expect(b.height == 4)
    }

    @Test func summaryFindsExtremes() {
        let points = [
            SurveyPoint(x: 0, y: 0, score: 90, rtt: nil, jitter: nil, loss: 0),
            SurveyPoint(x: 1, y: 0, score: 30, rtt: nil, jitter: nil, loss: 0),
            SurveyPoint(x: 2, y: 0, score: 60, rtt: nil, jitter: nil, loss: 0),
        ]
        let summary = SurveySummary(points: points)
        #expect(summary.average == 60)
        #expect(summary.weakest?.score == 30)
        #expect(summary.strongest?.score == 90)
        #expect(abs(summary.weakFraction - 1.0 / 3.0) < 0.0001)
    }

    @Test func surveyRoundTripsThroughJSON() throws {
        let survey = Survey(
            name: "Living", mode: .walk,
            points: [SurveyPoint(x: 1, y: 2, score: 70, rtt: 0.003, jitter: 0.001, loss: 0, bssid: "aa:bb")])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Survey.self, from: encoder.encode(survey))
        #expect(decoded.points.first?.bssid == "aa:bb")
        #expect(decoded.name == "Living")
    }
}

@Suite struct AgentQuotaTests {
    static let fixture = """
        {"providers":[
          {"provider":"claude_code","scope_id":"default","scope_label":"Claude","status":"ready",
           "windows":[
             {"id":"five_hour","label":"5-Hour Window","kind":"rolling_short","used_pct":0.0,"remaining_pct":100.0,"unit":"percent","window_minutes":300},
             {"id":"weekly","label":"Weekly Window","kind":"weekly","used_pct":74.0,"remaining_pct":26.0,"unit":"percent","window_minutes":10080,"resets_at":"2026-09-28T04:59:59.778055Z","resets_in_seconds":45975}],
           "credits":{"currency":"USD","remaining_amount":0.72},
           "fetched_at":"2026-09-27T16:13:01.396296Z","last_success_at":"2026-09-27T16:13:01.396296Z","is_stale":false},
          {"provider":"codex","scope_id":"x","scope_label":"ChatGPT","status":"rate_limited",
           "account":{"plan_name":"plus","email_masked":"user***.example"},
           "windows":[{"id":"five_hour","label":"5-Hour Window","kind":"rolling_short","used_pct":100.0,"remaining_pct":0.0,"window_minutes":300,"resets_at":"2026-09-27T16:39:15Z","resets_in_seconds":1530}],
           "fetched_at":"2026-09-27T16:13:41Z","is_stale":true},
          {"provider":"grok","scope_id":"g","status":"unavailable","windows":[]}
        ]}
        """

    @Test func decodesRealPayload() throws {
        let items = try AgentQuotaPayload.decode(Data(Self.fixture.utf8))
        #expect(items.count == 2)  // unavailable かつ空の grok は落とす
        let claude = try #require(items.first { $0.provider == "claude_code" })
        #expect(claude.primaryWindow?.id == "five_hour")
        #expect(claude.weeklyWindow?.remainingPct == 26)
        #expect(claude.credits == 0.72)
        #expect(claude.weeklyWindow?.resetsAt != nil)
        let codex = try #require(items.first { $0.provider == "codex" })
        #expect(codex.planName == "plus")
        #expect(codex.dataTimestamp != nil)
    }

    @Test func displayOrderKeepsSixFixedSlots() throws {
        let items = try AgentQuotaPayload.decode(Data(Self.fixture.utf8))
        let ordered = AgentQuotaProviderItem.displayOrder(items)
        #expect(ordered.prefix(6).map(\.provider) == AgentQuotaProviderItem.homeProviderIDs)
        #expect(ordered[0].provider == "codex" && ordered[0].hasData)
        #expect(ordered[2].scopeId == "home-placeholder")
    }

    @Test func shortWindowLevels() {
        #expect(QuotaLevel(remainingPct: 0, weekly: false) == .limited)
        #expect(QuotaLevel(remainingPct: 0.4, weekly: true) == .limited)
        #expect(QuotaLevel(remainingPct: 0.5, weekly: false) == .critical)
        #expect(QuotaLevel(remainingPct: 9.9, weekly: false) == .critical)
        #expect(QuotaLevel(remainingPct: 10, weekly: false) == .low)
        #expect(QuotaLevel(remainingPct: 19.9, weekly: false) == .low)
        #expect(QuotaLevel(remainingPct: 20, weekly: false) == .caution)
        #expect(QuotaLevel(remainingPct: 29.9, weekly: false) == .caution)
        #expect(QuotaLevel(remainingPct: 30, weekly: false) == .ok)
        #expect(QuotaLevel(remainingPct: 100, weekly: false) == .ok)
    }

    @Test func weeklyLevelsUseSevenths() {
        #expect(QuotaLevel(remainingPct: 14, weekly: true) == .critical)  // < 1/7
        #expect(QuotaLevel(remainingPct: 15, weekly: true) == .low)  // 1/7..2/7
        #expect(QuotaLevel(remainingPct: 28, weekly: true) == .low)
        #expect(QuotaLevel(remainingPct: 29, weekly: true) == .caution)  // 2/7..3/7
        #expect(QuotaLevel(remainingPct: 42, weekly: true) == .caution)
        #expect(QuotaLevel(remainingPct: 43, weekly: true) == .ok)  // >= 3/7
    }

    @Test func windowKindSelectsThresholds() {
        func window(_ kind: String, minutes: Int?, remaining: Double) -> AgentQuotaWindow {
            AgentQuotaWindow(
                id: kind, label: "", kind: kind, usedPct: 100 - remaining, remainingPct: remaining,
                windowMinutes: minutes, resetsAt: nil, resetsInSeconds: nil)
        }
        // 残り 25%: 5h なら黄、週次ならオレンジ
        #expect(window("rolling_short", minutes: 300, remaining: 25).level == .caution)
        #expect(window("weekly", minutes: 10080, remaining: 25).level == .low)
        // モデル別でも 7 日枠なら週次の段階
        #expect(window("model_specific", minutes: 10080, remaining: 25).level == .low)
        #expect(window("model_specific", minutes: 300, remaining: 25).level == .caution)
    }

    @Test func resetLabels() {
        let now = Date(timeIntervalSince1970: 0)
        let window = AgentQuotaWindow(
            id: "w", label: "", kind: "weekly", usedPct: 10, remainingPct: 90, windowMinutes: nil,
            resetsAt: now.addingTimeInterval(3 * 3600 + 20 * 60), resetsInSeconds: nil)
        #expect(AgentQuotaDisplay.resetLabel(for: window, now: now) == "3h20m")
        #expect(AgentQuotaDisplay.duration(seconds: 90000) == "1d1h")
        #expect(AgentQuotaDisplay.duration(seconds: 0) == "now")
    }

    @Test func staleOnlyAfterThreshold() {
        let now = Date()
        #expect(!AgentQuotaDisplay.shouldShowStaleState(isStale: true, timestamp: now.addingTimeInterval(-60), now: now))
        #expect(AgentQuotaDisplay.shouldShowStaleState(isStale: true, timestamp: now.addingTimeInterval(-700), now: now))
        #expect(!AgentQuotaDisplay.shouldShowStaleState(isStale: false, timestamp: now.addingTimeInterval(-700), now: now))
    }
}
