import MerutoCore
import SwiftUI

/// 電波マップ。補間したヒートマップの上に、歩いた軌跡・測定点・最弱/最強地点・現在地を重ねる。
struct SurveyMapView: View {
    let survey: Survey
    var livePose: ARPositionTracker.Pose?
    var pending: (x: Double, y: Double, progress: Double)?
    var onTap: ((Double, Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let bounds = displayBounds(aspect: size.width / max(1, size.height))
            let mapper = MapTransform(bounds: bounds, size: size)
            ZStack {
                MapGrid(bounds: bounds, mapper: mapper)
                HeatmapLayer(survey: survey, bounds: bounds)
                    .equatable()
                    .blur(radius: 6)
                    .allowsHitTesting(false)
                MarksLayer(survey: survey, mapper: mapper)
                if let livePose {
                    PoseMarker(heading: livePose.heading)
                        .position(mapper.point(livePose.x, livePose.y))
                        .animation(.linear(duration: 0.12), value: livePose)
                }
                if let pending {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.2), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: pending.progress)
                            .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: Theme.cyan, radius: 4)
                        Text("\(Int((1 - pending.progress) * SurveyRecorder.manualDuration + 0.9))")
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)
                    .position(mapper.point(pending.x, pending.y))
                }
                if survey.points.isEmpty && pending == nil {
                    emptyHint
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    guard let onTap else { return }
                    let meters = mapper.meters(value.location)
                    onTap(
                        min(max(meters.x, bounds.minX), bounds.maxX),
                        min(max(meters.y, bounds.minY), bounds.maxY))
                },
                including: onTap == nil ? .subviews : .all
            )
        }
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.panelStroke, lineWidth: 1)
        )
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: survey.mode == .walk ? "figure.walk.motion" : "hand.tap")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.cyan)
            Text(survey.mode == .walk ? "記録を開始して部屋を歩き回ってください" : "今いる場所をタップすると3秒間測定します")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.label)
                .multilineTextAlignment(.center)
        }
        .padding()
        .allowsHitTesting(false)
    }

    /// 表示範囲。歩行モードは現在地も含め、1m 単位に丸めて頻繁に揺れないようにする。
    private func displayBounds(aspect: Double) -> SurveyBounds {
        switch survey.mode {
        case .manual:
            return survey.bounds.fitted(toAspect: aspect)
        case .walk:
            var coordinates = survey.points.map { ($0.x, $0.y) }
            if let livePose { coordinates.append((livePose.x, livePose.y)) }
            var b = SurveyBounds.enclosing(coordinates, padding: 1.2, minimumSpan: 4)
            b.minX = b.minX.rounded(.down)
            b.maxX = b.maxX.rounded(.up)
            b.minY = b.minY.rounded(.down)
            b.maxY = b.maxY.rounded(.up)
            return b.fitted(toAspect: aspect)
        }
    }
}

/// メートル座標と画面座標の変換 (y は上が奥)。
struct MapTransform {
    var bounds: SurveyBounds
    var size: CGSize

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(
            x: (x - bounds.minX) / bounds.width * size.width,
            y: (bounds.maxY - y) / bounds.height * size.height)
    }

    func meters(_ p: CGPoint) -> (x: Double, y: Double) {
        (bounds.minX + Double(p.x / size.width) * bounds.width, bounds.maxY - Double(p.y / size.height) * bounds.height)
    }

    var pointsPerMeter: CGFloat { size.width / bounds.width }
}

/// 1m 方眼と縮尺。
private struct MapGrid: View {
    let bounds: SurveyBounds
    let mapper: MapTransform

    var body: some View {
        Canvas { context, size in
            var minor = Path()
            var x = bounds.minX.rounded(.up)
            while x <= bounds.maxX {
                let p = mapper.point(x, 0).x
                minor.move(to: CGPoint(x: p, y: 0))
                minor.addLine(to: CGPoint(x: p, y: size.height))
                x += 1
            }
            var y = bounds.minY.rounded(.up)
            while y <= bounds.maxY {
                let p = mapper.point(0, y).y
                minor.move(to: CGPoint(x: 0, y: p))
                minor.addLine(to: CGPoint(x: size.width, y: p))
                y += 1
            }
            context.stroke(minor, with: .color(Theme.cyan.opacity(0.10)), lineWidth: 0.7)

            // 縮尺 1m
            let scale = mapper.pointsPerMeter
            let origin = CGPoint(x: 12, y: size.height - 12)
            var bar = Path()
            bar.move(to: CGPoint(x: origin.x, y: origin.y - 4))
            bar.addLine(to: origin)
            bar.addLine(to: CGPoint(x: origin.x + scale, y: origin.y))
            bar.addLine(to: CGPoint(x: origin.x + scale, y: origin.y - 4))
            context.stroke(bar, with: .color(.white.opacity(0.6)), lineWidth: 1.2)
            context.draw(
                Text("1m").font(Theme.mono(9, weight: .bold)).foregroundColor(.white.opacity(0.7)),
                at: CGPoint(x: origin.x + scale / 2, y: origin.y - 10))
        }
        .allowsHitTesting(false)
    }
}

/// 補間画像。点数と範囲が変わらない限り作り直さない。
private struct HeatmapLayer: View, Equatable {
    let survey: Survey
    let bounds: SurveyBounds

    nonisolated static func == (lhs: HeatmapLayer, rhs: HeatmapLayer) -> Bool {
        lhs.survey.id == rhs.survey.id && lhs.survey.points.count == rhs.survey.points.count
            && lhs.survey.points.last == rhs.survey.points.last && lhs.bounds == rhs.bounds
    }

    var body: some View {
        if let image = HeatmapRenderer.image(for: survey, bounds: bounds, columns: 80) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
        }
    }
}

/// 軌跡・測定点・最弱/最強のマーカー。
private struct MarksLayer: View {
    let survey: Survey
    let mapper: MapTransform

    var body: some View {
        let summary = survey.summary
        Canvas { context, _ in
            if survey.mode == .walk, survey.points.count > 1 {
                var trail = Path()
                trail.move(to: mapper.point(survey.points[0].x, survey.points[0].y))
                for p in survey.points.dropFirst() { trail.addLine(to: mapper.point(p.x, p.y)) }
                context.stroke(
                    trail, with: .color(.white.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round, dash: [3, 3]))
            }
            let radius: CGFloat = survey.mode == .manual ? 5 : 3
            for p in survey.points {
                let c = mapper.point(p.x, p.y)
                let rect = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect.insetBy(dx: -1.2, dy: -1.2)), with: .color(.black.opacity(0.6)))
                context.fill(Path(ellipseIn: rect), with: .color(Theme.quality(p.score)))
            }
            if summary.count >= 3 {
                if let weakest = summary.weakest {
                    marker(context: context, point: weakest, label: "WEAK \(Int(weakest.score))", color: Theme.red)
                }
                if let strongest = summary.strongest {
                    marker(context: context, point: strongest, label: "BEST \(Int(strongest.score))", color: Theme.cyan)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func marker(context: GraphicsContext, point: SurveyPoint, label: String, color: Color) {
        let c = mapper.point(point.x, point.y)
        let ring = CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22)
        context.stroke(Path(ellipseIn: ring), with: .color(color), lineWidth: 2)
        let text = Text(label).font(Theme.mono(9, weight: .heavy)).foregroundColor(color)
        let resolved = context.resolve(text)
        let textSize = resolved.measure(in: CGSize(width: 200, height: 20))
        let box = CGRect(x: c.x - textSize.width / 2 - 4, y: c.y - 30, width: textSize.width + 8, height: textSize.height + 2)
        context.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.black.opacity(0.7)))
        context.draw(resolved, at: CGPoint(x: box.midX, y: box.midY))
    }
}

/// 現在地 (脈打つ円 + 向きの扇形)。
private struct PoseMarker: View {
    var heading: Double
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.cyan.opacity(0.25))
                .frame(width: pulse ? 40 : 18, height: pulse ? 40 : 18)
                .opacity(pulse ? 0 : 0.9)
            Cone()
                .fill(
                    RadialGradient(colors: [Theme.cyan.opacity(0.7), .clear], center: .bottom, startRadius: 0, endRadius: 34)
                )
                .frame(width: 44, height: 34)
                .offset(y: -17)
                .rotationEffect(.radians(heading))
            Circle()
                .fill(.white)
                .frame(width: 12, height: 12)
                .overlay(Circle().fill(Theme.cyan).padding(2.5))
                .shadow(color: Theme.cyan, radius: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    private struct Cone: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.minY - 8))
            path.closeSubpath()
            return path
        }
    }
}

/// 0...100 の色の凡例。
struct QualityLegend: View {
    var body: some View {
        VStack(spacing: 3) {
            Capsule()
                .fill(LinearGradient(stops: Theme.qualityGradientStops, startPoint: .leading, endPoint: .trailing))
                .frame(height: 6)
            HStack {
                Text("弱い")
                Spacer()
                Text("50")
                Spacer()
                Text("強い")
            }
            .font(Theme.mono(8.5, weight: .semibold))
            .foregroundStyle(Theme.faint)
        }
    }
}
