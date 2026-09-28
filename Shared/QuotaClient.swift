import Foundation
import MerutoCore

/// agent-quota (`GET /api/v1/quota`) の取得と、App Group への最終成功値のキャッシュ。
/// ウィジェットは失敗時もキャッシュで描く (取得できない = 白紙、にしない)。
enum QuotaClient {
    struct Result: Sendable {
        var providers: [AgentQuotaProviderItem]
        var fetchedAt: Date
        var isFromCache: Bool
    }

    enum Failure: Error {
        case badURL
        case http(Int)
    }

    static func fetch(baseURL: String = SharedContainer.quotaBaseURL, timeout: TimeInterval = 10) async throws -> Result {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty, let url = URL(string: trimmed + "/api/v1/quota"), url.scheme != nil else { throw Failure.badURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure.http(http.statusCode)
        }
        let providers = try AgentQuotaPayload.decode(data)
        let now = Date()
        SharedContainer.write(data, to: SharedContainer.File.quotaPayload)
        SharedContainer.write(Data(ISO8601DateFormatter().string(from: now).utf8), to: SharedContainer.File.quotaFetchedAt)
        return Result(providers: providers, fetchedAt: now, isFromCache: false)
    }

    static func cached() -> Result? {
        guard let data = SharedContainer.read(SharedContainer.File.quotaPayload),
            let providers = try? AgentQuotaPayload.decode(data)
        else { return nil }
        let fetchedAt = SharedContainer.read(SharedContainer.File.quotaFetchedAt)
            .flatMap { ISO8601DateFormatter().date(from: String(decoding: $0, as: UTF8.self)) } ?? .distantPast
        return Result(providers: providers, fetchedAt: fetchedAt, isFromCache: true)
    }

    /// 取得を試み、失敗したらキャッシュを返す。
    static func fetchOrCached() async -> Result? {
        if let fresh = try? await fetch() { return fresh }
        return cached()
    }

    /// ウィジェット選択画面や初回用のサンプル。
    static let sample: [AgentQuotaProviderItem] = {
        let now = Date()
        func window(_ kind: String, _ remaining: Double, _ resetIn: TimeInterval, minutes: Int) -> AgentQuotaWindow {
            AgentQuotaWindow(
                id: kind, label: kind, kind: kind, usedPct: 100 - remaining, remainingPct: remaining,
                windowMinutes: minutes, resetsAt: now.addingTimeInterval(resetIn), resetsInSeconds: nil)
        }
        func item(_ provider: String, _ label: String, five: Double?, week: Double?, credits: Double? = nil, status: String = "ready")
            -> AgentQuotaProviderItem
        {
            var windows: [AgentQuotaWindow] = []
            if let five { windows.append(window("rolling_short", five, 2 * 3600 + 840, minutes: 300)) }
            if let week { windows.append(window("weekly", week, 3 * 86400 + 7200, minutes: 10080)) }
            return AgentQuotaProviderItem(
                provider: provider, scopeId: "sample", scopeLabel: label, status: status, planName: nil,
                emailMasked: nil, windows: windows, credits: credits, currency: credits == nil ? nil : "USD",
                isStale: false, dataTimestamp: now, lastErrorMessage: nil)
        }
        return [
            item("codex", "ChatGPT", five: 8, week: 80),
            item("claude_code", "Claude", five: 72, week: 26),
            item("antigravity", "agy CLI", five: 91, week: 50),
            item("zai", "Z.ai", five: 100, week: 94),
            item("deepseek", "DeepSeek", five: nil, week: nil, credits: 12.4),
            item("devin", "Devin", five: nil, week: 61),
        ]
    }()
}
