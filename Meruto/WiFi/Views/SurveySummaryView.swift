import MerutoCore
import SwiftUI

struct SurveySummaryView: View {
    let survey: Survey

    var body: some View {
        let summary = survey.summary
        if summary.count > 0 {
            HStack(spacing: 0) {
                item("測定点", "\(summary.count)", .white)
                item("平均", summary.average.map { "\(Int($0.rounded()))" } ?? "—", Theme.quality(summary.average ?? 0))
                item("最弱", summary.weakest.map { "\(Int($0.score.rounded()))" } ?? "—", Theme.red)
                item("最強", summary.strongest.map { "\(Int($0.score.rounded()))" } ?? "—", Theme.cyan)
                item("弱い範囲", Format.percent(summary.weakFraction), summary.weakFraction > 0.2 ? Theme.orange : .white)
            }
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
            if let weakest = summary.weakest, let strongest = summary.strongest, summary.count >= 3 {
                Text(advice(weakest: weakest, strongest: strongest))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func advice(weakest: SurveyPoint, strongest: SurveyPoint) -> String {
        let distance = hypot(weakest.x - strongest.x, weakest.y - strongest.y)
        let grade = QualityGrade(score: weakest.score)
        if weakest.score >= 60 {
            return "マップ全体で電波は十分です（最弱地点でも「\(grade.label)」）。"
        }
        return "最弱地点（WEAK）は最強地点から約\(String(format: "%.1f", distance))m 離れた場所で「\(grade.label)」です。"
            + "ルーターの位置を WEAK 側へ寄せるか、中継機・メッシュの追加を検討してください。"
    }

    private func item(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(Theme.mono(8.5, weight: .semibold))
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(Theme.rounded(15))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}
