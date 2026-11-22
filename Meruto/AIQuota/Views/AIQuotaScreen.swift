import MerutoCore
import SwiftUI

/// AI 使用量の画面。上にコンパクトなゲージカード、下にタップで詳細シートが開くプロバイダー一覧。
struct AIQuotaScreen: View {
    let store: AgentQuotaStore
    var onOpenSettings: () -> Void
    @State private var selectedGroup: AgentQuotaProviderGroup?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ScreenTitle(title: "AI USAGE", subtitle: "agent-quota · Tailscale")
                Panel(title: "Providers", icon: "sparkles", tint: Theme.quotaGreen) {
                    statusBadge
                } content: {
                    AgentQuotaHomeCard(store: store, onOpenDetail: {}, initiallyExpanded: false)
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Panel(title: "Accounts & Limits", icon: "list.bullet.rectangle", tint: Theme.cyan) {
                        Text("\(store.providers.count) scopes")
                            .font(Theme.mono(9, weight: .bold))
                            .foregroundStyle(Theme.label)
                    } content: {
                        VStack(spacing: 0) {
                            let groups = store.allGroups.filter { $0.representative.hasData }
                            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                                if index > 0 {
                                    Divider().overlay(Color.white.opacity(0.06))
                                }
                                providerSummaryRow(group, now: context.date)
                            }
                        }
                    }
                }
                connectionPanel
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
        .sheet(item: $selectedGroup) { group in
            ProviderDetailSheet(providerID: group.provider, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func providerSummaryRow(_ group: AgentQuotaProviderGroup, now: Date) -> some View {
        let rep = group.representative
        return Button {
            selectedGroup = group
        } label: {
            HStack(spacing: 10) {
                AgentBrandIconView(provider: group.provider, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(rep.providerDisplayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        if group.scopeCount > 1 {
                            Text("\(group.scopeCount)")
                                .font(Theme.mono(9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.10), in: Capsule())
                        }
                        if group.hasHiddenConstraint {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                        }
                    }
                    let extraCount = group.scopes.reduce(0) { $0 + $1.windows.count }
                    if extraCount > 0 {
                        Text("\(extraCount) 枠 · タップで詳細")
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.faint)
                    }
                }
                Spacer()
                if let win = rep.primaryWindow {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(AgentQuotaDisplay.percentLabel(for: win.remainingPct, detailed: true))
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundStyle(AgentQuotaStyle.gaugeColor(for: win))
                        if let reset = AgentQuotaDisplay.resetLabel(for: win, now: now) {
                            Text("↻ \(reset)")
                                .font(Theme.mono(9))
                                .foregroundStyle(Theme.label)
                        }
                    }
                } else if let creds = rep.credits {
                    Text("\(rep.currency ?? "$") \(String(format: "%.2f", creds))")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(.cyan)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            if store.isRefreshing {
                ProgressView().controlSize(.mini).tint(Theme.label)
            }
            LiveBadge(active: store.isDaemonRunning, label: "SYNC")
        }
    }

    private var connectionPanel: some View {
        Panel(title: "Connection", icon: "network", tint: Theme.blue) {
            VStack(alignment: .leading, spacing: 8) {
                Text(SharedContainer.quotaBaseURL)
                    .font(Theme.mono(10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                if let lastUpdated = store.lastUpdated, lastUpdated > .distantPast {
                    Text("最終取得 \(lastUpdated.formatted(date: .omitted, time: .standard))")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.label)
                }
                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.orange)
                }
                Button("接続先を変更", action: onOpenSettings)
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.bordered)
                    .tint(Theme.cyan)
            }
        }
    }
}
