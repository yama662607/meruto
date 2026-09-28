import MerutoCore
import SwiftUI

struct AIQuotaCard: View {
    let store: AgentQuotaStore
    var onOpen: () -> Void

    var body: some View {
        Panel(title: "AI Usage", icon: "sparkles", tint: Theme.quotaGreen) {
            Button(action: onOpen) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.label)
            }
        } content: {
            AgentQuotaHomeCard(store: store, onOpenDetail: onOpen)
        }
    }
}
