import Foundation

/// 電波マップの測定モード。
public enum SurveyMode: String, Codable, Sendable {
    /// ARKit で端末の位置を追跡し、歩きながら自動で測る。
    case walk
    /// 部屋の見取り図上で自分の位置をタップして、その場で測る。
    case manual
}

/// 1 地点の測定値。座標はメートル (x: 右、y: 奥)。
public struct SurveyPoint: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var x: Double
    public var y: Double
    public var score: Double
    public var rtt: TimeInterval?
    public var jitter: TimeInterval?
    public var loss: Double
    public var bssid: String?
    public var timestamp: Date

    public init(
        id: UUID = UUID(), x: Double, y: Double, score: Double, rtt: TimeInterval?, jitter: TimeInterval?,
        loss: Double, bssid: String? = nil, timestamp: Date = Date()
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.score = score
        self.rtt = rtt
        self.jitter = jitter
        self.loss = loss
        self.bssid = bssid
        self.timestamp = timestamp
    }
}

public struct Survey: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var mode: SurveyMode
    public var createdAt: Date
    public var updatedAt: Date
    public var points: [SurveyPoint]
    /// 手動モードの見取り図の大きさ (m)。
    public var roomWidth: Double
    public var roomDepth: Double

    public init(
        id: UUID = UUID(), name: String, mode: SurveyMode, createdAt: Date = Date(), points: [SurveyPoint] = [],
        roomWidth: Double = 8, roomDepth: Double = 6
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.points = points
        self.roomWidth = roomWidth
        self.roomDepth = roomDepth
    }

    public var summary: SurveySummary { SurveySummary(points: points) }

    /// 表示範囲。手動モードは部屋の大きさ、歩行モードは測定点を囲む範囲 (+余白)。
    public var bounds: SurveyBounds {
        switch mode {
        case .manual:
            SurveyBounds(minX: 0, maxX: roomWidth, minY: 0, maxY: roomDepth)
        case .walk:
            SurveyBounds.enclosing(points.map { ($0.x, $0.y) }, padding: 1.2, minimumSpan: 4)
        }
    }
}

public struct SurveyBounds: Sendable, Equatable {
    public var minX: Double
    public var maxX: Double
    public var minY: Double
    public var maxY: Double

    public init(minX: Double, maxX: Double, minY: Double, maxY: Double) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }

    /// 点群を囲み、`padding` の余白を足し、どちらの辺も `minimumSpan` 以上にする (中心は保つ)。
    public static func enclosing(_ points: [(Double, Double)], padding: Double, minimumSpan: Double) -> SurveyBounds {
        guard let first = points.first else {
            let half = minimumSpan / 2
            return SurveyBounds(minX: -half, maxX: half, minY: -half, maxY: half)
        }
        var b = SurveyBounds(minX: first.0, maxX: first.0, minY: first.1, maxY: first.1)
        for (x, y) in points {
            b.minX = min(b.minX, x)
            b.maxX = max(b.maxX, x)
            b.minY = min(b.minY, y)
            b.maxY = max(b.maxY, y)
        }
        b.minX -= padding
        b.maxX += padding
        b.minY -= padding
        b.maxY += padding
        if b.width < minimumSpan {
            let grow = (minimumSpan - b.width) / 2
            b.minX -= grow
            b.maxX += grow
        }
        if b.height < minimumSpan {
            let grow = (minimumSpan - b.height) / 2
            b.minY -= grow
            b.maxY += grow
        }
        return b
    }

    /// 縦横比 `aspect` (幅/高さ) に合うよう、短い方の辺を広げる。
    public func fitted(toAspect aspect: Double) -> SurveyBounds {
        guard aspect > 0, width > 0, height > 0 else { return self }
        var b = self
        if width / height < aspect {
            let target = height * aspect
            let grow = (target - width) / 2
            b.minX -= grow
            b.maxX += grow
        } else {
            let target = width / aspect
            let grow = (target - height) / 2
            b.minY -= grow
            b.maxY += grow
        }
        return b
    }
}

public struct SurveySummary: Sendable, Equatable {
    public var count: Int
    public var average: Double?
    public var weakest: SurveyPoint?
    public var strongest: SurveyPoint?
    /// スコア 40 未満の点の割合。
    public var weakFraction: Double

    public init(points: [SurveyPoint]) {
        count = points.count
        average = points.isEmpty ? nil : points.map(\.score).reduce(0, +) / Double(points.count)
        weakest = points.min { $0.score < $1.score }
        strongest = points.max { $0.score < $1.score }
        weakFraction = points.isEmpty ? 0 : Double(points.filter { $0.score < 40 }.count) / Double(points.count)
    }
}

/// 格子状に補間したスコア。`values` は行優先 (上の行から)、`alpha` は測定点からの近さ。
public struct Heatmap: Sendable, Equatable {
    public var columns: Int
    public var rows: Int
    public var values: [Double]
    public var alpha: [Double]

    public func value(column: Int, row: Int) -> Double { values[row * columns + column] }
    public func opacity(column: Int, row: Int) -> Double { alpha[row * columns + column] }
}

public enum HeatmapBuilder {
    /// 逆距離加重 (IDW) で補間する。測定点から `solidRadius` までは不透明、
    /// `fadeRadius` で透明になる (測っていない場所を推測で塗りつぶさないため)。
    /// 行 0 が `bounds.maxY` (画面の上 = 奥) になる。
    public static func build(
        points: [SurveyPoint], bounds: SurveyBounds, columns: Int, rows: Int,
        power: Double = 2, solidRadius: Double = 0.9, fadeRadius: Double = 2.4
    ) -> Heatmap {
        var values = [Double](repeating: 0, count: columns * rows)
        var alpha = [Double](repeating: 0, count: columns * rows)
        guard !points.isEmpty, columns > 0, rows > 0 else {
            return Heatmap(columns: columns, rows: rows, values: values, alpha: alpha)
        }
        let cellW = bounds.width / Double(columns)
        let cellH = bounds.height / Double(rows)
        for row in 0..<rows {
            let y = bounds.maxY - (Double(row) + 0.5) * cellH
            for column in 0..<columns {
                let x = bounds.minX + (Double(column) + 0.5) * cellW
                var weightSum = 0.0
                var valueSum = 0.0
                var nearest = Double.infinity
                var exact: Double?
                for p in points {
                    let dx = p.x - x
                    let dy = p.y - y
                    let d = (dx * dx + dy * dy).squareRoot()
                    nearest = min(nearest, d)
                    if d < 0.0001 {
                        exact = p.score
                        break
                    }
                    let w = 1 / pow(d, power)
                    weightSum += w
                    valueSum += w * p.score
                }
                let index = row * columns + column
                values[index] = exact ?? valueSum / weightSum
                if nearest <= solidRadius {
                    alpha[index] = 1
                } else if nearest >= fadeRadius {
                    alpha[index] = 0
                } else {
                    let t = (nearest - solidRadius) / (fadeRadius - solidRadius)
                    alpha[index] = 1 - t * t * (3 - 2 * t)
                }
            }
        }
        return Heatmap(columns: columns, rows: rows, values: values, alpha: alpha)
    }
}
