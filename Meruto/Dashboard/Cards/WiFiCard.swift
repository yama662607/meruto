import MerutoCore
import SwiftUI

struct WiFiCard: View {
    let monitor: DeviceMonitor
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Panel(title: "Wi-Fi", icon: "wifi", tint: Theme.cyan) {
                if let wifi = monitor.latestWiFi {
                    let grade = QualityGrade(score: wifi.score)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(wifi.score.rounded()))")
                            .font(Theme.rounded(28, weight: .heavy))
                            .foregroundStyle(Theme.quality(wifi.score))
                        SignalBars(bars: grade.bars, color: Theme.quality(wifi.score))
                    }
                    Text(grade.label)
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("電波測定器")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 4) {
                    Text("測定を開く")
                    Image(systemName: "chevron.right")
                }
                .font(Theme.mono(9.5, weight: .bold))
                .foregroundStyle(Theme.cyan)
            }
        }
        .buttonStyle(.plain)
    }
}
