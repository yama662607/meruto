import MerutoCore
import MerutoProbes
import SwiftUI

struct CPUCard: View {
    let monitor: DeviceMonitor

    var body: some View {
        let total = monitor.cpu?.total.total ?? 0
        let color = Theme.severity(UsageThresholds.standard.severity(for: total), base: Theme.cyan)
        Panel(title: "CPU", icon: "cpu", tint: Theme.cyan) {
            LiveBadge(active: monitor.cpu != nil)
        } content: {
            HStack(spacing: 16) {
                RingGauge(value: total, colors: [Theme.blue, color], lineWidth: 10, ticks: 40) {
                    VStack(spacing: 0) {
                        Text(monitor.cpu == nil ? "--" : "\(Int((total * 100).rounded()))")
                            .font(Theme.rounded(34, weight: .heavy))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("% LOAD")
                            .font(Theme.mono(9, weight: .bold))
                            .foregroundStyle(Theme.label)
                    }
                }
                .frame(width: 124, height: 124)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        Readout(label: "User", value: Format.percent(monitor.cpu?.total.user ?? 0), color: Theme.cyan)
                        Readout(label: "System", value: Format.percent(monitor.cpu?.total.system ?? 0), color: Theme.magenta)
                    }
                    Readout(label: "Cores", value: coreDescription, size: 13)
                    Sparkline(values: monitor.cpuHistory.elements, maxValue: 1, color: color)
                        .frame(height: 38)
                }
            }
            CoreBars(cores: monitor.cpu?.cores ?? Array(repeating: 0, count: monitor.system.logicalCores),
                     performance: monitor.system.performanceCores)
                .frame(height: 46)
        }
    }

    private var coreDescription: String {
        let system = monitor.system
        if let p = system.performanceCores, let e = system.efficiencyCores {
            return "\(system.logicalCores)  (\(p)P + \(e)E)"
        }
        return "\(system.logicalCores)"
    }
}

/// コアごとの縦バー。高性能コアはシアン、高効率コアは緑。
private struct CoreBars: View {
    var cores: [Double]
    var performance: Int?

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(cores.enumerated()), id: \.offset) { index, value in
                let isPerformance = index < (performance ?? cores.count)
                let color = isPerformance ? Theme.cyan : Theme.green
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [color.opacity(0.5), color], startPoint: .bottom, endPoint: .top))
                                .frame(height: max(2, geo.size.height * value))
                                .shadow(color: color.opacity(0.6), radius: 3)
                        }
                    }
                    Text(isPerformance ? "P" : "E")
                        .font(Theme.mono(8, weight: .bold))
                        .foregroundStyle(color.opacity(0.7))
                }
                .animation(.smooth(duration: 0.5), value: value)
            }
        }
    }
}
