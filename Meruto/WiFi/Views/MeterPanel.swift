import MerutoCore
import SwiftUI

struct MeterPanel: View {
    let meter: WiFiMeter
    @Binding var geigerEnabled: Bool

    var body: some View {
        let score = meter.smoothedScore
        let color = score.map(Theme.quality) ?? Theme.faint
        Panel(title: "Link Quality", icon: "wifi", tint: color) {
            LiveBadge(active: meter.state == .measuring, label: "MEASURING")
        } content: {
            ZStack(alignment: .bottom) {
                ArcMeter(value: score)
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 2) {
                    Text(score.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 64, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .shadow(color: color.opacity(0.8), radius: 12)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.3), value: score.map { Int($0.rounded()) })
                    HStack(spacing: 8) {
                        SignalBars(bars: meter.grade?.bars ?? 0, color: color)
                        Text(statusText)
                            .font(Theme.mono(13, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(color)
                    }
                    if let grade = meter.grade, meter.state == .measuring {
                        Text(grade.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .padding(.bottom, 4)
            }
            HStack(spacing: 0) {
                stat("RTT", meter.stats.medianRTT.map { Format.milliseconds($0) } ?? "—", rttColor)
                divider
                stat("Jitter", meter.stats.jitter.map { Format.milliseconds($0) } ?? "—", .white)
                divider
                stat("Loss", Format.percent(meter.stats.loss), meter.stats.loss > 0.05 ? Theme.orange : .white)
                divider
                stat("推定レート", meter.stats.estimatedRate.map { Format.bitRate(bitsPerSecond: $0) } ?? "—", Theme.cyan)
            }
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))

            HStack {
                Toggle(isOn: $geigerEnabled) {
                    Label("振動で強さを知らせる", systemImage: "waveform.path")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .tint(Theme.cyan)
            }
            if let bssid = meter.bssid {
                Text("BSSID \(bssid)")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.faint)
            }
        }
    }

    private var statusText: String {
        switch meter.state {
        case .idle: "STANDBY"
        case .resolving: "SEARCHING"
        case .noWiFi: "NO Wi-Fi"
        case .noGateway: "NO ROUTER"
        case .measuring: meter.grade?.code ?? "CALIBRATING"
        }
    }

    private var rttColor: Color {
        guard let rtt = meter.stats.medianRTT else { return .white }
        return Theme.quality(100 - min(100, rtt * 1000))
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 28)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(Theme.mono(8.5, weight: .semibold))
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(Theme.rounded(14))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}
