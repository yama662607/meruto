import MerutoCore
import MerutoProbes
import SwiftUI

struct StorageCard: View {
    let monitor: DeviceMonitor

    var body: some View {
        let storage = monitor.storage
        let fraction = storage?.usedFraction ?? 0
        let color = Theme.severity(UsageThresholds(warning: 0.85, critical: 0.95).severity(for: fraction), base: Theme.blue)
        Panel(title: "Storage", icon: "internaldrive", tint: Theme.blue) {
            HStack(spacing: 12) {
                RingGauge(value: fraction, colors: [Theme.violet, color], lineWidth: 7) {
                    Text(Format.percent(fraction))
                        .font(Theme.rounded(14, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 6) {
                    Readout(label: "Free", value: storage.map { Format.bytes($0.available) } ?? "--", size: 14)
                    Readout(label: "Total", value: storage.map { Format.bytes($0.total) } ?? "--", size: 11)
                }
            }
        }
    }
}
