import Foundation

// iOS には Wi-Fi の RSSI を読む公開 API が無い (NEHotspotNetwork.signalStrength は
// Hotspot Helper 専用で、通常のアプリでは常に 0)。そこで既定ゲートウェイ (= Wi-Fi ルーター)
// へ ICMP Echo を高頻度で打ち、無線区間の状態を実測する。
//
// - 電波が弱いと PHY レートが下がり、再送が増えるので RTT とそのばらつき (ジッタ) が伸びる。
// - さらに弱いと応答が返らなくなる (ロス)。
// - 小さいパケットと大きいパケットの RTT 差は「無線区間でのデータの滞在時間」なので、
//   そこから実効リンクレートを推定できる (弱い場所ほど差が開く)。
//
// これらを 0...100 のリンク品質スコアに畳み込んで表示する。dBm は測っていないので名乗らない。

/// 1 回の ICMP Echo の結果。`rtt` が nil ならタイムアウト (ロス)。
public struct PingResult: Sendable, Equatable {
    public var rtt: TimeInterval?
    public var payloadSize: Int
    public var timestamp: Date

    public init(rtt: TimeInterval?, payloadSize: Int, timestamp: Date = Date()) {
        self.rtt = rtt
        self.payloadSize = payloadSize
        self.timestamp = timestamp
    }
}

/// 直近の窓から求めた統計。
public struct LinkStats: Sendable, Equatable {
    /// 小パケット RTT の中央値 (秒)。
    public var medianRTT: TimeInterval?
    /// 連続する RTT の差の絶対値の平均 (秒)。RFC 3550 のジッタに近い。
    public var jitter: TimeInterval?
    /// 0...1
    public var loss: Double
    /// 大小パケットの RTT 差から推定した実効レート (bits/s)。
    public var estimatedRate: Double?
    /// 0...100
    public var score: Double?
    public var sampleCount: Int

    public init(
        medianRTT: TimeInterval?, jitter: TimeInterval?, loss: Double, estimatedRate: Double?,
        score: Double?, sampleCount: Int
    ) {
        self.medianRTT = medianRTT
        self.jitter = jitter
        self.loss = loss
        self.estimatedRate = estimatedRate
        self.score = score
        self.sampleCount = sampleCount
    }

    public static let empty = LinkStats(
        medianRTT: nil, jitter: nil, loss: 0, estimatedRate: nil, score: nil, sampleCount: 0)
}

public enum LinkQuality {
    /// RTT・ジッタ・ロスから 0...100 のスコアを出す。どれも対数で効かせる
    /// (3ms→6ms の悪化も 30ms→60ms の悪化も同じだけ効くように)。
    public static func score(rtt: TimeInterval, jitter: TimeInterval, loss: Double) -> Double {
        let rttScore = 1 - logRamp(rtt * 1000, good: 3, bad: 200)
        let jitterScore = 1 - logRamp(jitter * 1000, good: 1, bad: 80)
        let lossScore = 1 - clamp(loss / 0.25)
        let combined = 0.5 * rttScore + 0.25 * jitterScore + 0.25 * lossScore
        // ロスが増えると RTT が良くても信用できないので、全体に掛けて効かせる。
        return 100 * combined * (1 - clamp(loss * 2) * 0.8)
    }

    /// `good` 以下で 0、`bad` 以上で 1、その間を対数で補間する。
    static func logRamp(_ value: Double, good: Double, bad: Double) -> Double {
        guard value > good else { return 0 }
        return clamp((log10(value) - log10(good)) / (log10(bad) - log10(good)))
    }

    static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    /// 大小 2 種類のパケットの RTT 中央値から実効レート (bits/s) を推定する。
    /// 往復なので 2 倍のバイト数が無線区間を通る。差が小さすぎる (測定誤差以下) ときは nil。
    public static func estimatedRate(
        smallRTT: TimeInterval, smallSize: Int, largeRTT: TimeInterval, largeSize: Int
    ) -> Double? {
        let delta = largeRTT - smallRTT
        guard largeSize > smallSize, delta > 0.000_05 else { return nil }
        let bits = Double(2 * (largeSize - smallSize) * 8)
        return min(bits / delta, 2_400_000_000)
    }
}

public enum QualityGrade: Int, Sendable, CaseIterable {
    case poor, weak, fair, good, excellent

    public init(score: Double) {
        switch score {
        case 80...: self = .excellent
        case 60..<80: self = .good
        case 40..<60: self = .fair
        case 20..<40: self = .weak
        default: self = .poor
        }
    }

    public var label: String {
        switch self {
        case .excellent: "非常に良好"
        case .good: "良好"
        case .fair: "普通"
        case .weak: "弱い"
        case .poor: "圏外寸前"
        }
    }

    public var code: String {
        switch self {
        case .excellent: "EXCELLENT"
        case .good: "GOOD"
        case .fair: "FAIR"
        case .weak: "WEAK"
        case .poor: "POOR"
        }
    }

    /// 0...4 本のアンテナ表示。
    public var bars: Int { rawValue }
}

/// ping の結果を溜めて統計を出す。小パケットと大パケットを別々の窓で持つ。
public struct LinkQualityAnalyzer: Sendable {
    public let smallPayload: Int
    public let largePayload: Int
    private var small: RingBuffer<PingResult>
    private var large: RingBuffer<PingResult>

    public init(smallPayload: Int = 56, largePayload: Int = 1_400, window: Int = 30) {
        self.smallPayload = smallPayload
        self.largePayload = largePayload
        small = RingBuffer(capacity: window)
        large = RingBuffer(capacity: max(8, window / 2))
    }

    public mutating func add(_ result: PingResult) {
        if result.payloadSize >= largePayload {
            large.append(result)
        } else {
            small.append(result)
        }
    }

    public mutating func reset() {
        small.removeAll()
        large.removeAll()
    }

    public var stats: LinkStats {
        let smallResults = small.elements
        guard !smallResults.isEmpty else { return .empty }
        let rtts = smallResults.compactMap(\.rtt)
        let lost = smallResults.count - rtts.count
        let loss = Double(lost) / Double(smallResults.count)

        guard let median = Self.median(rtts) else {
            return LinkStats(
                medianRTT: nil, jitter: nil, loss: loss, estimatedRate: nil,
                score: smallResults.count >= 3 ? 0 : nil, sampleCount: smallResults.count)
        }

        var jitter: TimeInterval = 0
        if rtts.count >= 2 {
            let diffs = zip(rtts.dropFirst(), rtts).map { abs($0 - $1) }
            jitter = diffs.reduce(0, +) / Double(diffs.count)
        }

        var rate: Double?
        let largeRTTs = large.elements.compactMap(\.rtt)
        if rtts.count >= 5, largeRTTs.count >= 4, let largeMedian = Self.median(largeRTTs) {
            rate = LinkQuality.estimatedRate(
                smallRTT: median, smallSize: smallPayload, largeRTT: largeMedian, largeSize: largePayload)
        }

        return LinkStats(
            medianRTT: median,
            jitter: jitter,
            loss: loss,
            estimatedRate: rate,
            score: LinkQuality.score(rtt: median, jitter: jitter, loss: loss),
            sampleCount: smallResults.count)
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

/// スコアの色。0 (赤) → 25 (橙) → 50 (黄) → 75 (緑) → 100 (シアン)。
public enum QualityColor {
    public struct RGB: Sendable, Equatable {
        public var r: Double
        public var g: Double
        public var b: Double
    }

    static let stops: [(Double, RGB)] = [
        (0, RGB(r: 1.00, g: 0.16, b: 0.35)),
        (25, RGB(r: 1.00, g: 0.46, b: 0.12)),
        (50, RGB(r: 1.00, g: 0.84, b: 0.10)),
        (75, RGB(r: 0.22, g: 0.92, b: 0.46)),
        (100, RGB(r: 0.10, g: 0.84, b: 1.00)),
    ]

    public static func rgb(for score: Double) -> RGB {
        let s = min(100, max(0, score))
        for (index, stop) in stops.enumerated().dropFirst() {
            let previous = stops[index - 1]
            if s <= stop.0 {
                let t = (s - previous.0) / (stop.0 - previous.0)
                return RGB(
                    r: previous.1.r + (stop.1.r - previous.1.r) * t,
                    g: previous.1.g + (stop.1.g - previous.1.g) * t,
                    b: previous.1.b + (stop.1.b - previous.1.b) * t)
            }
        }
        return stops[stops.count - 1].1
    }
}
