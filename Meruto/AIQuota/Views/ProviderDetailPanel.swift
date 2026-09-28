import MerutoCore
import SwiftUI

struct ProviderDetailPanel: View {
    let item: AgentQuotaProviderItem
    let now: Date

    var body: some View {
        Panel(title: item.providerDisplayName, icon: "circle.hexagongrid.fill", tint: statusColor) {
            Text(statusText)
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(statusColor)
        } content: {
            HStack(spacing: 10) {
                AgentBrandIconView(provider: item.provider, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.scopeLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    if let detail = [item.planName?.uppercased(), item.emailMasked].compactMap({ $0 }).joined(separator: " · ")
                        .nilIfEmpty
                    {
                        Text(detail)
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.label)
                    }
                }
                Spacer()
                if let credits = item.credits {
                    Readout(label: item.currency ?? "Credits", value: String(format: "%.2f", credits), color: .cyan, size: 16)
                }
            }
            ForEach(item.windows) { window in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(window.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        Spacer()
                        Text("残り \(Int(window.remainingPct))%")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(AgentQuotaStyle.gaugeColor(for: window))
                        if let reset = AgentQuotaDisplay.resetLabel(for: window, now: now) {
                            Text("↻ \(reset)")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(AgentQuotaStyle.resetColor(for: window, now: now).opacity(0.7))
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AgentQuotaStyle.barTrackColor(for: window, normalOpacity: 0.08))
                            if window.level != .limited {
                                Capsule()
                                    .fill(AgentQuotaStyle.gaugeGradient(for: window))
                                    .frame(width: geo.size.width * min(1, window.remainingPct / 100))
                            }
                        }
                    }
                    .frame(height: 5)
                }
            }
            if let message = item.lastErrorMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.orange.opacity(0.8))
                    .lineLimit(2)
            }
            if let age = AgentQuotaDisplay.ageLabel(for: item.dataTimestamp, now: now) {
                Text(age)
                    .font(Theme.mono(9))
                    .foregroundStyle(item.isStale ? Theme.orange : Theme.faint)
            }
        }
    }

    private var statusColor: Color {
        switch item.status {
        case "ready": Theme.quotaGreen
        case "warning", "degraded": .orange
        case "rate_limited": AgentQuotaStyle.rateLimitedColor
        case "unauthorized": .red
        default: .gray
        }
    }

    private var statusText: String {
        switch item.status {
        case "ready": "利用可能"
        case "warning": "残量わずか"
        case "rate_limited": "制限中"
        case "degraded": "一部利用不可"
        case "unauthorized": "要再認証"
        default: item.status
        }
    }
}
