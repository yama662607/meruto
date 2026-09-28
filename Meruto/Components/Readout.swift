import SwiftUI

/// 小さなラベル付きの数値。
struct Readout: View {
    var label: String
    var value: String
    var unit: String? = nil
    var color: Color = .white
    var size: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Theme.mono(9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.faint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.rounded(size))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(Theme.mono(size * 0.55, weight: .medium))
                        .foregroundStyle(Theme.label)
                }
            }
        }
    }
}
