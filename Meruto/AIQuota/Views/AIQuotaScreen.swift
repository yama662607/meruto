import MerutoCore
import SwiftUI

/// AI 使用量の画面。上に SuperNotch と同じカード、下にプロバイダーごとの内訳。
struct AIQuotaScreen: View {
    let store: AgentQuotaStore
    var onOpenSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ScreenTitle(title: "AI USAGE", subtitle: "agent-quota · Tailscale")
                Panel(title: "Providers", icon: "sparkles", tint: Theme.quotaGreen) {
                    statusBadge
                } content: {
                    AgentQuotaHomeCard(store: store, onOpenDetail: {}, initiallyExpanded: true)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 12) {
                        ForEach(store.displayedProviders.filter(\.hasData)) { item in
                            ProviderDetailPanel(item: item, now: context.date)
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
