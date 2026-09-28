import MerutoCore
import SwiftUI

/// SuperNotch のホームカードをそのまま移植したもの。タップで週次枠と追加プロバイダーを展開する。
struct AgentQuotaHomeCard: View {
    let store: AgentQuotaStore
    let onOpenDetail: () -> Void
    @State private var isExpanded: Bool

    init(store: AgentQuotaStore, onOpenDetail: @escaping () -> Void, initiallyExpanded: Bool = false) {
        self.store = store
        self.onOpenDetail = onOpenDetail
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let displayed = store.displayedProviders
        VStack(alignment: .leading, spacing: 4) {
            // Keep the six core providers visible even while the daemon is
            // unavailable or a provider has not returned data yet.
            AgentQuotaGaugeRow(providers: displayed, now: now)

            // 展開時: 固定表示以外のプロバイダーや週次枠を表示
            if !store.providers.isEmpty && isExpanded {
                Divider().overlay(Color.white.opacity(0.06))

                let others = Array(displayed.dropFirst(AgentQuotaProviderItem.homeProviderIDs.count))
                if !others.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(others) { item in
                            AgentQuotaMiniGauge(item: item, now: now)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                }

                AgentQuotaWeeklyBars(providers: displayed)
            }

            if !store.isDaemonRunning {
                HStack {
                    Text(store.isShowingCache ? "前回取得した値を表示中" : "AI使用量の連携を利用できません")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("再確認") {
                        Task { await store.refresh() }
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.smooth(duration: 0.22)) {
                isExpanded.toggle()
            }
        }
    }
}
