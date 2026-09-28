import MerutoCore
import SwiftUI

/// 保存済みの電波マップ一覧。
struct SurveyListView: View {
    let store: SurveyStore
    var onSelect: (Survey) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Survey?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if store.surveys.isEmpty {
                    Text("まだマップがありません")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.surveys) { survey in
                    Button {
                        onSelect(survey)
                        dismiss()
                    } label: {
                        row(survey)
                    }
                    .listRowBackground(survey.id == store.currentID ? Theme.cyan.opacity(0.12) : Color.white.opacity(0.04))
                    .swipeActions {
                        Button(role: .destructive) {
                            store.delete(survey.id)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        Button {
                            newName = survey.name
                            renaming = survey
                        } label: {
                            Label("名前", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(InstrumentBackground())
            .navigationTitle("電波マップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("名前を変更", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("名前", text: $newName)
                Button("保存") {
                    if var survey = renaming {
                        survey.name = newName
                        store.update(survey)
                    }
                    renaming = nil
                }
                Button("キャンセル", role: .cancel) { renaming = nil }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ survey: Survey) -> some View {
        let summary = survey.summary
        return HStack(spacing: 12) {
            HeatmapThumbnail(survey: survey)
                .frame(width: 64, height: 48)
                .background(Color.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(survey.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(survey.mode == .walk ? "AR" : "タップ") · \(summary.count)点 · \(survey.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.label)
            }
            Spacer()
            if let average = summary.average {
                Text("\(Int(average.rounded()))")
                    .font(Theme.rounded(20, weight: .heavy))
                    .foregroundStyle(Theme.quality(average))
            }
        }
    }
}
