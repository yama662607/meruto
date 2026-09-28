import MerutoCore
import SwiftUI

struct ThermalCard: View {
    let monitor: DeviceMonitor

    var body: some View {
        let level = monitor.thermal
        let color = Theme.severity(level.severity, base: Theme.cyan)
        Panel(title: "Thermal", icon: "thermometer.medium", tint: color) {
            Text(level.englishLabel)
                .font(Theme.rounded(20, weight: .heavy))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.6), radius: 6)
            HStack(spacing: 3) {
                ForEach(ThermalLevel.allCases, id: \.rawValue) { step in
                    let stepColor = Theme.severity(step.severity, base: Theme.cyan)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(step.rawValue <= level.rawValue ? stepColor : Color.white.opacity(0.07))
                        .frame(height: 10)
                        .shadow(color: step == level ? stepColor : .clear, radius: 4)
                }
            }
            Text(level.label)
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text("iOSは温度の実測値を公開していないため熱状態（4段階）を表示")
                .font(.system(size: 8.5))
                .foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
