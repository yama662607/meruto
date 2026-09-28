import MerutoCore
import SwiftUI

struct BatteryCard: View {
    let monitor: DeviceMonitor

    var body: some View {
        let level = monitor.batteryLevel
        let severity = batterySeverity(level: level, state: monitor.chargeState)
        let color = Theme.severity(severity, base: monitor.chargeState == .charging ? Theme.green : Theme.lime)
        Panel(title: "Battery", icon: monitor.chargeState == .charging ? "bolt.fill" : "battery.75percent", tint: color) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(level.map { "\(Int(($0 * 100).rounded()))" } ?? "--")
                    .font(Theme.rounded(34, weight: .heavy))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("%").font(Theme.mono(14, weight: .bold)).foregroundStyle(Theme.label)
            }
            BatteryGlyph(level: level ?? 0, color: color, charging: monitor.chargeState == .charging)
                .frame(height: 26)
            HStack {
                Text(monitor.chargeState.label)
                    .font(Theme.mono(9.5, weight: .semibold))
                    .foregroundStyle(Theme.label)
                Spacer()
                if monitor.lowPowerMode {
                    Text("低電力")
                        .font(Theme.mono(8.5, weight: .bold))
                        .foregroundStyle(Theme.yellow)
                }
            }
        }
    }
}

private struct BatteryGlyph: View {
    var level: Double
    var color: Color
    var charging: Bool

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                    SegmentBar(value: level, segments: 10, color: { _ in color }, spacing: 2)
                        .padding(4)
                    if charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 3, height: geo.size.height * 0.4)
            }
        }
    }
}
