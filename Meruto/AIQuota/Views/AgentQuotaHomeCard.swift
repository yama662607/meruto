import MerutoCore
import SwiftUI

/// ホームの AI 使用量カード。
/// Personal / Team などのアカウントは個別のゲージとして並べ、
/// 各ゲージをタップするとそのアカウントの詳細シート（全枠・モデル別・絶対数）を開く。
struct AgentQuotaHomeCard: View {
    let store: AgentQuotaStore
    let onOpenDetail: () -> Void
    @State private var showMoreProviders: Bool
    @State private var selectedItem: AgentQuotaProviderItem?

    init(store: AgentQuotaStore, onOpenDetail: @escaping () -> Void, initiallyExpanded: Bool = false) {
        self.store = store
        self.onOpenDetail = onOpenDetail
        _showMoreProviders = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
        .sheet(item: $selectedItem) { item in
            ProviderDetailSheet(
                itemID: item.id,
                fallbackItem: item,
                store: store
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let home = store.homeItems
        let extras = store.extraItems

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 3) {
                ForEach(home) { item in
                    tappableGauge(item, now: now)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 2)

            if !store.providers.isEmpty && showMoreProviders && !extras.isEmpty {
                Divider().overlay(Color.white.opacity(0.06))
                HStack(spacing: 3) {
                    ForEach(extras) { item in
                        tappableGauge(item, now: now)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 2)
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
            } else if !extras.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            showMoreProviders.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(showMoreProviders ? "閉じる" : "+\(extras.count)")
                                .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                            Image(systemName: showMoreProviders ? "chevron.up" : "chevron.down")
                                .font(.system(size: 7.5, weight: .bold))
                        }
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func tappableGauge(_ item: AgentQuotaProviderItem, now: Date) -> some View {
        Button {
            selectedItem = item
        } label: {
            AgentQuotaMiniGauge(
                item: item,
                now: now,
                hasHiddenConstraint: item.hasConstrainedSubWindow
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
