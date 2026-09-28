import SwiftUI

/// 計測器のパネル。左上にアイコン付きのラベル、右上に任意のアクセサリ。
struct Panel<Content: View, Accessory: View>: View {
    var title: String
    var icon: String
    var tint: Color = Theme.cyan
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.8), radius: 4)
                Text(title.uppercased())
                    .font(Theme.mono(10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.label)
                Spacer(minLength: 4)
                accessory()
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.065), Color.white.opacity(0.025)], startPoint: .topLeading,
                        endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [tint.opacity(0.35), Theme.panelStroke, Theme.panelStroke.opacity(0.4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
        )
    }
}

extension Panel where Accessory == EmptyView {
    init(title: String, icon: String, tint: Color = Theme.cyan, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, icon: icon, tint: tint, accessory: { EmptyView() }, content: content)
    }
}
