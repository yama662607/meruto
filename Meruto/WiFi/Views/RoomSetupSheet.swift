import SwiftUI

struct RoomSetupSheet: View {
    @Binding var width: Double
    @Binding var depth: Double
    var onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $width, in: 2...30, step: 0.5) {
                        LabeledContent("横幅", value: String(format: "%.1f m", width))
                    }
                    Stepper(value: $depth, in: 2...30, step: 0.5) {
                        LabeledContent("奥行き", value: String(format: "%.1f m", depth))
                    }
                } footer: {
                    Text("おおよその大きさで構いません。マップ上で今いる場所をタップすると、その地点を3秒間測定します。")
                }
            }
            .navigationTitle("部屋の大きさ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("開始") {
                        onStart()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}
