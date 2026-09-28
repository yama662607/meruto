import MerutoCore
import SwiftUI

/// 計測器風のダークテーマ。アプリとウィジェットで同じ色を使う。
enum Theme {
    static let background = Color(red: 0.020, green: 0.028, blue: 0.055)
    static let backgroundTop = Color(red: 0.045, green: 0.070, blue: 0.135)
    static let panel = Color.white.opacity(0.045)
    static let panelStroke = Color.white.opacity(0.09)
    static let grid = Color(red: 0.3, green: 0.7, blue: 1).opacity(0.05)
    static let label = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.32)

    static let cyan = Color(red: 0.10, green: 0.84, blue: 1.00)
    static let green = Color(red: 0.22, green: 0.92, blue: 0.46)
    static let lime = Color(red: 0.72, green: 0.95, blue: 0.20)
    static let yellow = Color(red: 1.00, green: 0.84, blue: 0.10)
    static let orange = Color(red: 1.00, green: 0.50, blue: 0.14)
    static let red = Color(red: 1.00, green: 0.18, blue: 0.36)
    static let magenta = Color(red: 0.98, green: 0.30, blue: 0.85)
    static let violet = Color(red: 0.58, green: 0.45, blue: 1.00)
    static let blue = Color(red: 0.30, green: 0.55, blue: 1.00)

    /// SuperNotch の AI 使用量ゲージと同じ落ち着いたグリーン。
    static let quotaGreen = Color(red: 0.18, green: 0.72, blue: 0.36)

    static func severity(_ severity: Severity, base: Color) -> Color {
        switch severity {
        case .normal: base
        case .warning: yellow
        case .serious: orange
        case .critical: red
        }
    }

    static func quality(_ score: Double) -> Color {
        let rgb = QualityColor.rgb(for: score)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    static var qualityGradientStops: [Gradient.Stop] {
        stride(from: 0.0, through: 100.0, by: 12.5).map { Gradient.Stop(color: quality($0), location: $0 / 100) }
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// 深い紺のグラデーション + うっすらとした方眼。
struct InstrumentBackground: View {
    var gridSpacing: CGFloat = 24

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.backgroundTop, Theme.background], startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += gridSpacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += gridSpacing
                }
                context.stroke(path, with: .color(Theme.grid), lineWidth: 0.5)
            }
            RadialGradient(
                colors: [Theme.cyan.opacity(0.10), .clear], center: .top, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}
