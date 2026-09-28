import SwiftUI

/// 光るリングゲージ。`value` は 0...1。
struct RingGauge<Center: View>: View {
    var value: Double
    var colors: [Color]
    var lineWidth: CGFloat = 8
    var glow: Bool = true
    var ticks: Int = 0
    @ViewBuilder var center: () -> Center

    var body: some View {
        let clamped = min(1, max(0, value))
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)
            if ticks > 0 {
                TickRing(count: ticks)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .padding(lineWidth + 3)
            }
            Circle()
                .trim(from: 0, to: max(0.002, clamped))
                .stroke(
                    AngularGradient(
                        colors: colors, center: .center, startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(0.05, clamped))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: glow ? (colors.last ?? .white).opacity(0.55) : .clear, radius: lineWidth * 0.9)
            center()
        }
        .animation(.smooth(duration: 0.6), value: clamped)
    }
}

extension RingGauge where Center == EmptyView {
    init(value: Double, colors: [Color], lineWidth: CGFloat = 8, glow: Bool = true, ticks: Int = 0) {
        self.init(value: value, colors: colors, lineWidth: lineWidth, glow: glow, ticks: ticks) { EmptyView() }
    }
}

/// 円周上の短い目盛り。
struct TickRing: Shape {
    var count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi
            let long = i % 5 == 0
            let inner = radius - (long ? 5 : 2.5)
            path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
        }
        return path
    }
}

/// LED 風のセグメントバー。`value` は 0...1。
struct SegmentBar: View {
    var value: Double
    var segments: Int = 20
    var color: (Double) -> Color
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let lit = Int((min(1, max(0, value)) * Double(segments)).rounded())
            HStack(spacing: spacing) {
                ForEach(0..<segments, id: \.self) { index in
                    let position = Double(index) / Double(max(1, segments - 1))
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(index < lit ? color(position) : Color.white.opacity(0.07))
                        .shadow(color: index < lit ? color(position).opacity(0.6) : .clear, radius: 3)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// 直近の推移を描く細い線グラフ。`values` は古い順。
struct Sparkline: View {
    var values: [Double]
    var maxValue: Double? = nil
    var color: Color
    var lineWidth: CGFloat = 1.6
    var fill: Bool = true

    var body: some View {
        GeometryReader { geo in
            let upper = max(maxValue ?? (values.max() ?? 1), 0.000_001)
            let points = normalizedPoints(size: geo.size, upper: upper)
            ZStack {
                if fill, points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                }
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .shadow(color: color.opacity(0.6), radius: 3)
                if let last = points.last {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .shadow(color: color, radius: 4)
                        .position(last)
                }
            }
        }
    }

    private func normalizedPoints(size: CGSize, upper: Double) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let y = size.height - CGFloat(min(1, max(0, value / upper))) * (size.height - 3) - 1.5
            return CGPoint(x: CGFloat(index) * step, y: y)
        }
    }
}

/// 計測器風のアーチメーター。0...100 のスコアと針。
struct ArcMeter: View {
    var value: Double?
    var sweep: Double = 240
    var segmentCount: Int = 48

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height / 0.86)
            let radius = side / 2
            let center = CGPoint(x: geo.size.width / 2, y: radius)
            let startAngle = 90 + (360 - sweep) / 2  // SwiftUI の角度は時計回り・右が 0°
            ZStack {
                Canvas { context, _ in
                    for i in 0..<segmentCount {
                        let t = Double(i) / Double(segmentCount - 1)
                        let angle = Angle.degrees(startAngle + sweep * t).radians
                        let major = i % 4 == 0
                        let outer = radius - 2
                        let inner = radius - (major ? radius * 0.16 : radius * 0.11)
                        var path = Path()
                        path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                        path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                        let lit = (value ?? -1) >= t * 100
                        let color = Theme.quality(t * 100)
                        context.stroke(
                            path, with: .color(lit ? color : color.opacity(0.14)),
                            style: StrokeStyle(lineWidth: major ? 4 : 3, lineCap: .round))
                    }
                    // 内側の細い目盛り円弧
                    var arc = Path()
                    arc.addArc(
                        center: center, radius: radius * 0.72, startAngle: .degrees(startAngle),
                        endAngle: .degrees(startAngle + sweep), clockwise: false)
                    context.stroke(arc, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                    // 数字
                    for mark in stride(from: 0, through: 100, by: 25) {
                        let angle = Angle.degrees(startAngle + sweep * Double(mark) / 100).radians
                        let r = radius * 0.62
                        let text = Text("\(mark)").font(.system(size: max(9, radius * 0.075), weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                        context.draw(text, at: CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r))
                    }
                }
                .shadow(color: Theme.quality(value ?? 0).opacity(value == nil ? 0 : 0.45), radius: 8)

                // 針
                let needleT = (value ?? 0) / 100
                Needle(length: radius * 0.80)
                    .fill(
                        LinearGradient(colors: [.white, .white.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 8, height: radius * 0.80 * 2)
                    .rotationEffect(.degrees(startAngle + sweep * needleT + 90))
                    .position(center)
                    .shadow(color: .white.opacity(0.6), radius: 6)
                    .opacity(value == nil ? 0.25 : 1)
                    .animation(.interpolatingSpring(stiffness: 70, damping: 11), value: needleT)
                Circle()
                    .fill(Color.white)
                    .frame(width: radius * 0.1, height: radius * 0.1)
                    .overlay(Circle().fill(Theme.background).padding(radius * 0.028))
                    .position(center)
            }
        }
        .aspectRatio(1 / 0.86, contentMode: .fit)
    }
}

/// 中心から上へ伸びる細い針 (フレームの中央が回転中心)。
struct Needle: Shape {
    var length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        path.move(to: CGPoint(x: cx, y: cy - length))
        path.addLine(to: CGPoint(x: cx + rect.width / 2, y: cy))
        path.addLine(to: CGPoint(x: cx, y: cy + length * 0.12))
        path.addLine(to: CGPoint(x: cx - rect.width / 2, y: cy))
        path.closeSubpath()
        return path
    }
}

/// アンテナ本数表示 (0...4)。
struct SignalBars: View {
    var bars: Int
    var color: Color
    var total: Int = 4

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < bars ? color : Color.white.opacity(0.15))
                    .frame(width: 4, height: CGFloat(5 + index * 4))
            }
        }
    }
}
