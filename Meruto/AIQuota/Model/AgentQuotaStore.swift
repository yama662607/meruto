import Foundation
import MerutoCore
import WidgetKit

/// Mac の agent-quota デーモン (Tailscale 経由) から AI の使用状況を取る。
/// 画面に出ている間だけ 15 秒ごとに取り直す。取れないときは最後に成功した値を出す。
@MainActor @Observable
final class AgentQuotaStore {
    private(set) var providers: [AgentQuotaProviderItem] = []
    /// 直近の取得が成功したか (SuperNotch の `isDaemonRunning` に相当)。
    private(set) var isDaemonRunning = false
    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    private(set) var isShowingCache = false

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var visibleCount = 0

    init() {
        if let cached = QuotaClient.cached() {
            providers = cached.providers
            lastUpdated = cached.fetchedAt
            isShowingCache = true
        }
    }

    var displayedProviders: [AgentQuotaProviderItem] {
        AgentQuotaProviderItem.displayOrder(providers)
    }

    /// 複数の画面から参照されるので、表示中の数を数えて 0 になったら止める。
    func setVisible(_ visible: Bool) {
        visibleCount = max(0, visibleCount + (visible ? 1 : -1))
        if visibleCount > 0, pollTask == nil {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                }
            }
        } else if visibleCount == 0 {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await QuotaClient.fetch()
            let hadData = !providers.isEmpty
            providers = result.providers
            lastUpdated = result.fetchedAt
            isDaemonRunning = true
            isShowingCache = false
            lastError = nil
            if !hadData { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.aiQuota) }
        } catch {
            isDaemonRunning = false
            lastError = Self.describe(error)
            if providers.isEmpty, let cached = QuotaClient.cached() {
                providers = cached.providers
                lastUpdated = cached.fetchedAt
            }
            isShowingCache = !providers.isEmpty
        }
    }

    private static func describe(_ error: Error) -> String {
        if let failure = error as? QuotaClient.Failure {
            switch failure {
            case .badURL: return "接続先URLが未設定か正しくありません (設定タブ)"
            case .http(let code): return "HTTP \(code)"
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed: return "ホストが見つかりません (Tailscale 接続を確認)"
            case .timedOut: return "タイムアウト"
            case .notConnectedToInternet: return "オフライン"
            case .cannotConnectToHost: return "接続できません (tailscale serve を確認)"
            default: return urlError.localizedDescription
            }
        }
        if error is DecodingError { return "応答の形式が想定と違います" }
        return error.localizedDescription
    }
}
