import MerutoCore
import SwiftUI

struct ScopePanel: View {
    let meter: WiFiMeter

    var body: some View {
        Panel(title: "Scope", icon: "waveform.path.ecg", tint: Theme.green) {
            Text("\(meter.packetsSent - meter.packetsLost)/\(meter.packetsSent) PKT")
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(Theme.faint)
        } content: {
            ZStack {
                ScopeGrid()
                ScoreTrace(values: meter.scoreHistory.elements)
                Sparkline(
                    values: meter.rttHistory.elements.map { min($0, 100) }, maxValue: 100, color: Theme.magenta.opacity(0.8),
                    lineWidth: 1, fill: false)
            }
            .frame(height: 110)
            HStack(spacing: 14) {
                legend("スコア", Theme.green)
                legend("RTT (0–100ms)", Theme.magenta)
                Spacer()
                Text("直近 25 秒")
                    .font(Theme.mono(8.5))
                    .foregroundStyle(Theme.faint)
            }
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 10, height: 3)
            Text(label).font(Theme.mono(8.5, weight: .medium)).foregroundStyle(Theme.label)
        }
    }
}

private struct ScopeGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for i in 0...4 {
                let y = size.height * CGFloat(i) / 4
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            for i in 0...10 {
                let x = size.width * CGFloat(i) / 10
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(path, with: .color(Theme.green.opacity(0.08)), lineWidth: 0.6)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.3)))
    }
}

/// スコアの推移。線の色は各時点のスコアの色。
private struct ScoreTrace: View {
    var values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(150 - 1)
            let offset = CGFloat(150 - values.count) * step
            func point(_ index: Int) -> CGPoint {
                CGPoint(x: offset + CGFloat(index) * step, y: size.height - CGFloat(values[index] / 100) * (size.height - 4) - 2)
            }
            for index in 1..<values.count {
                var segment = Path()
                segment.move(to: point(index - 1))
                segment.addLine(to: point(index))
                context.stroke(
                    segment, with: .color(Theme.quality(values[index])),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
        }
        .shadow(color: Theme.green.opacity(0.5), radius: 4)
    }
}
