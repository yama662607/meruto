import SwiftUI

/// 画面上部の大きな見出し。
struct ScreenTitle: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.cyan], startPoint: .leading, endPoint: .trailing))
                    .shadow(color: Theme.cyan.opacity(0.45), radius: 8)
                Text(subtitle)
                    .font(Theme.mono(10.5, weight: .medium))
                    .foregroundStyle(Theme.label)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}
