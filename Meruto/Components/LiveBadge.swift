import SwiftUI

/// 点滅する LIVE 表示。
struct LiveBadge: View {
    var active: Bool = true
    var label = "LIVE"
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? Theme.green : Theme.faint)
                .frame(width: 6, height: 6)
                .shadow(color: active ? Theme.green : .clear, radius: pulse ? 5 : 1)
                .opacity(active && pulse ? 0.45 : 1)
            Text(active ? label : "IDLE")
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(active ? Theme.green : Theme.faint)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
