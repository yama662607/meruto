import SwiftUI

/// ウィジェット共通の背景 (純黒)。
struct WidgetBackground: View {
    var body: some View {
        Color.black
    }
}

/// ウィジェット左上の小さな見出し。
struct WidgetHeader<Trailing: View>: View {
    var title: String
    var icon: String
    var tint: Color
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(Theme.mono(9, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.label)
            Spacer(minLength: 2)
            trailing()
        }
    }
}

extension WidgetHeader where Trailing == EmptyView {
    init(title: String, icon: String, tint: Color) {
        self.init(title: title, icon: icon, tint: tint) { EmptyView() }
    }
}

/// WidgetKit の completion は Sendable でないが、呼び出し元のスレッドに依存しないので
/// Task へ持ち込むために包む。
struct CompletionBox<T>: @unchecked Sendable {
    let call: (T) -> Void
}
