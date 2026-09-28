import MerutoCore
import SwiftUI

struct GPUCard: View {
    let monitor: DeviceMonitor

    var body: some View {
        let gpu = monitor.gpu
        let fpsFraction = monitor.displayFPS / Double(max(1, monitor.maxFPS))
        Panel(title: "GPU", icon: "square.stack.3d.up.fill", tint: Theme.magenta) {
            HStack(spacing: 12) {
                RingGauge(value: fpsFraction, colors: [Theme.violet, Theme.magenta], lineWidth: 7) {
                    VStack(spacing: -1) {
                        Text("\(Int(monitor.displayFPS.rounded()))")
                            .font(Theme.rounded(16, weight: .heavy))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("FPS").font(Theme.mono(7.5, weight: .bold)).foregroundStyle(Theme.label)
                    }
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Readout(label: "Family", value: gpu.family, size: 13)
                    Readout(label: "Display", value: "\(monitor.maxFPS)", unit: "Hz", size: 13)
                }
            }
            Text(gpu.name)
                .font(Theme.mono(9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 10) {
                Readout(label: "Working set", value: Format.bytes(gpu.recommendedWorkingSet), size: 11)
                Readout(label: "RT", value: gpu.supportsRaytracing ? "YES" : "NO", size: 11)
            }
            Text("iOSはGPU使用率を公開していません")
                .font(.system(size: 8.5))
                .foregroundStyle(Theme.faint)
        }
    }
}
