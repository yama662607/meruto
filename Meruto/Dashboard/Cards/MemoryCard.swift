import MerutoCore
import MerutoProbes
import SwiftUI

struct MemoryCard: View {
    let monitor: DeviceMonitor

    var body: some View {
        let memory = monitor.memory
        let fraction = memory?.usedFraction ?? 0
        let color = Theme.severity(UsageThresholds.standard.severity(for: fraction), base: Theme.violet)
        Panel(title: "Memory", icon: "memorychip", tint: Theme.violet) {
            HStack(spacing: 12) {
                RingGauge(value: fraction, colors: [Theme.blue, color], lineWidth: 7) {
                    Text(Format.percent(fraction))
                        .font(Theme.rounded(15, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Readout(label: "Used", value: memory.map { Format.bytes($0.used) } ?? "--", size: 14)
                    Readout(label: "Total", value: Format.bytes(monitor.system.physicalMemory), size: 12)
                }
            }
            if let memory {
                MemoryBreakdownBar(memory: memory)
                    .frame(height: 7)
                HStack(spacing: 8) {
                    legend("App", Theme.cyan)
                    legend("Wired", Theme.magenta)
                    legend("圧縮", Theme.orange)
                }
                if let own = memory.ownFootprint {
                    Text("このアプリ \(Format.bytes(own))")
                        .font(Theme.mono(9, weight: .medium))
                        .foregroundStyle(Theme.faint)
                }
            }
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(Theme.mono(8.5, weight: .medium)).foregroundStyle(Theme.label)
        }
    }
}

private struct MemoryBreakdownBar: View {
    let memory: MemoryUsage

    var body: some View {
        GeometryReader { geo in
            let total = Double(max(memory.total, 1))
            let parts: [(Double, Color)] = [
                (Double(memory.app), Theme.cyan),
                (Double(memory.wired), Theme.magenta),
                (Double(memory.compressed), Theme.orange),
                (Double(memory.cached), Theme.violet.opacity(0.45)),
            ]
            HStack(spacing: 1.5) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle()
                        .fill(part.1)
                        .frame(width: max(0, geo.size.width * part.0 / total - 1.5))
                }
                Spacer(minLength: 0)
            }
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
        }
    }
}
