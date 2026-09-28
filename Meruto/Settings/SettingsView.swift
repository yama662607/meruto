import MerutoCore
import SwiftUI
import WidgetKit

struct SettingsView: View {
    let quotaStore: AgentQuotaStore
    @State private var baseURL = SharedContainer.quotaBaseURL
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://<host>.<tailnet>.ts.net:10000", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                    HStack {
                        Button("保存して接続テスト") { Task { await saveAndTest() } }
                            .disabled(testing)
                        Spacer()
                        if testing { ProgressView() }
                    }
                    Button("既定に戻す") {
                        baseURL = SharedContainer.defaultQuotaBaseURL
                    }
                    if let testResult {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(testResult.hasPrefix("✓") ? .green : .orange)
                    }
                } header: {
                    Text("AI使用量 (agent-quota)")
                } footer: {
                    Text(
                        "Macで `tailscale serve --bg --https=10000 http://127.0.0.1:8765` を実行し、このiPhoneを同じtailnetに参加させてください。ウィジェットも同じURLから取得します。"
                    )
                }

                Section("共有 (App Group)") {
                    LabeledContent("状態", value: SharedContainer.isAppGroupAvailable ? "有効" : "無効（ウィジェットへ測定値を共有できません）")
                    Button("ウィジェットを更新") { WidgetCenter.shared.reloadAllTimelines() }
                }

                Section("このアプリについて") {
                    LabeledContent("バージョン", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    Text("CPU・メモリ・通信量は mach / sysctl / getifaddrs で端末から直接読みます。Wi-Fi の品質はルーターへの ICMP 応答から実測します（iOSは電波強度の値を公開していないため）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(InstrumentBackground())
            .navigationTitle("設定")
        }
    }

    private func saveAndTest() async {
        SharedContainer.quotaBaseURL = baseURL
        testing = true
        defer { testing = false }
        do {
            let result = try await QuotaClient.fetch(baseURL: baseURL)
            testResult = "✓ \(result.providers.count) 件のプロバイダーを取得しました"
            await quotaStore.refresh()
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.aiQuota)
        } catch {
            testResult = "接続できませんでした: \(error.localizedDescription)"
        }
    }
}
