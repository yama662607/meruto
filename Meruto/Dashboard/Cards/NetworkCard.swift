import MerutoCore
import MerutoProbes
import SwiftUI

struct NetworkCard: View {
    let monitor: DeviceMonitor

    var body: some View {
        let rate = monitor.network?.combined ?? .zero
        let upper = max(64 * 1024, (monitor.downloadHistory.elements + monitor.uploadHistory.elements).max() ?? 0)
        Panel(title: "Network", icon: "arrow.up.arrow.down", tint: Theme.green) {
            Text(monitor.path.interface + (monitor.radioTechnology.map { " · \($0)" } ?? ""))
                .font(Theme.mono(9.5, weight: .bold))
                .foregroundStyle(monitor.path.status == .satisfied ? Theme.green : Theme.red)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        } content: {
            HStack(alignment: .top, spacing: 18) {
                rateReadout(icon: "arrow.down", label: "Download", value: rate.download, color: Theme.green)
                rateReadout(icon: "arrow.up", label: "Upload", value: rate.upload, color: Theme.orange)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PING 1.1.1.1")
                        .font(Theme.mono(9, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                    Text(monitor.internetLatency.map { Format.milliseconds($0) } ?? "—")
                        .font(Theme.rounded(17))
                        .foregroundStyle(latencyColor)
                    Sparkline(values: monitor.latencyHistory.elements, maxValue: 200, color: latencyColor, lineWidth: 1.2, fill: false)
                        .frame(width: 70, height: 16)
                }
            }
            ZStack {
                Sparkline(values: monitor.downloadHistory.elements, maxValue: upper, color: Theme.green)
                Sparkline(values: monitor.uploadHistory.elements, maxValue: upper, color: Theme.orange, fill: false)
            }
            .frame(height: 56)
            HStack(spacing: 14) {
                ForEach(monitor.addresses.filter { $0.kind != .other }, id: \.name) { address in
                    Readout(
                        label: address.kind == .wifi ? "Wi-Fi IP" : "Cellular IP", value: address.addressString, size: 11)
                }
                Readout(
                    label: "Session",
                    value: "↓\(Format.bytes(monitor.network?.totalReceived ?? 0)) ↑\(Format.bytes(monitor.network?.totalSent ?? 0))",
                    size: 11)
                Spacer(minLength: 0)
                if monitor.path.isExpensive { flag("EXPENSIVE", Theme.orange) }
                if monitor.path.isConstrained { flag("LOW DATA", Theme.yellow) }
            }
        }
    }

    private var latencyColor: Color {
        guard let latency = monitor.internetLatency else { return Theme.red }
        if latency < 0.05 { return Theme.green }
        if latency < 0.15 { return Theme.yellow }
        return Theme.orange
    }

    private func rateReadout(icon: String, label: String, value: Double, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(color)
                .shadow(color: color, radius: 4)
                .padding(.top, 12)
            Readout(label: label, value: Format.rate(value), color: .white, size: 19)
        }
    }

    private func flag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(Theme.mono(8, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
    }
}
