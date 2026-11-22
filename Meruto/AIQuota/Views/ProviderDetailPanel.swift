import MerutoCore
import SwiftUI

struct ProviderDetailPanel: View {
    let item: AgentQuotaProviderItem
    let now: Date
    var showTitleHeader: Bool = true

    var body: some View {
        Panel(
            title: showTitleHeader ? item.providerDisplayName : (item.scopeLabel.isEmpty ? item.scopeId : item.scopeLabel),
            icon: "circle.hexagongrid.fill",
            tint: statusColor
        ) {
            Text(statusText)
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(statusColor)
        } content: {
            HStack(spacing: 10) {
                AgentBrandIconView(provider: item.provider, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.scopeLabel.isEmpty ? item.scopeId : item.scopeLabel)
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

            if item.windows.isEmpty && item.credits == nil {
                Text("クォータ情報なし")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
            }

            ForEach(item.windows) { window in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(window.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let units = window.unitsSummary {
                            Text(units)
                                .font(Theme.mono(9.5, weight: .medium))
                                .foregroundStyle(Theme.label)
                        }
                        Text("残り \(AgentQuotaDisplay.percentLabel(for: window.remainingPct, detailed: true))")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(AgentQuotaStyle.gaugeColor(for: window))
                        if let reset = AgentQuotaDisplay.resetLabel(for: window, now: now) {
                            let abs = AgentQuotaDisplay.absoluteResetLabel(for: window, now: now)
                            Text(abs.map { "↻ \(reset) (\($0))" } ?? "↻ \(reset)")
                                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
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

                    if let models = window.modelIds, !models.isEmpty {
                        let joined = models.joined(separator: ", ")
                        if joined.caseInsensitiveCompare(window.label) != .orderedSame {
                            Text(joined)
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.faint)
                                .lineLimit(2)
                        }
                    }
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

/// ゲージまたは一覧行タップで開くプロバイダー詳細ハーフシート。
/// 複数アカウント（Personal / Team 等）とすべてのウィンドウ（Argon / 3p / MCP 等）を表示する。
struct ProviderDetailSheet: View {
    let providerID: String
    let store: AgentQuotaStore
    @Environment(\.dismiss) private var dismiss
    @State private var isRefreshingProvider = false

    private var group: AgentQuotaProviderGroup {
        store.allGroups.first { $0.provider == providerID }
            ?? AgentQuotaProviderGroup(provider: providerID, scopes: [.homePlaceholder(provider: providerID)])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 12) {
                        ForEach(group.scopes) { scope in
                            ProviderDetailPanel(
                                item: scope,
                                now: context.date,
                                showTitleHeader: group.scopes.count <= 1
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(group.representative.providerDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            isRefreshingProvider = true
                            await store.refreshProvider(providerID)
                            isRefreshingProvider = false
                        }
                    } label: {
                        if isRefreshingProvider {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshingProvider)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
