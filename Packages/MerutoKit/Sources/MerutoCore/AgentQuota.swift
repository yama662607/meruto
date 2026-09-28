import Foundation

// SuperNotch の AgentQuota モジュールを iOS 向けに移植したもの。
// データ源は Mac で動く agent-quota デーモンの `GET /api/v1/quota`。

public struct AgentQuotaWindow: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let kind: String
    public let usedPct: Double
    public let remainingPct: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let resetsInSeconds: Int?

    public init(
        id: String, label: String, kind: String, usedPct: Double, remainingPct: Double,
        windowMinutes: Int?, resetsAt: Date?, resetsInSeconds: Int?
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.usedPct = usedPct
        self.remainingPct = remainingPct
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetsInSeconds = resetsInSeconds
    }
}

public struct AgentQuotaProviderItem: Identifiable, Sendable, Equatable {
    public static let homeProviderIDs = ["codex", "claude_code", "antigravity", "zai", "deepseek", "devin"]
    static let additionalProviderOrder = ["grok", "moonshot"]

    public var id: String { provider + ":" + scopeId }
    public let provider: String
    public let scopeId: String
    public let scopeLabel: String
    public let status: String
    public let planName: String?
    public let emailMasked: String?
    public let windows: [AgentQuotaWindow]
    public let credits: Double?
    public let currency: String?
    public let isStale: Bool
    public let dataTimestamp: Date?
    public let lastErrorMessage: String?

    public init(
        provider: String, scopeId: String, scopeLabel: String, status: String, planName: String?,
        emailMasked: String?, windows: [AgentQuotaWindow], credits: Double?, currency: String?,
        isStale: Bool, dataTimestamp: Date?, lastErrorMessage: String?
    ) {
        self.provider = provider
        self.scopeId = scopeId
        self.scopeLabel = scopeLabel
        self.status = status
        self.planName = planName
        self.emailMasked = emailMasked
        self.windows = windows
        self.credits = credits
        self.currency = currency
        self.isStale = isStale
        self.dataTimestamp = dataTimestamp
        self.lastErrorMessage = lastErrorMessage
    }

    public var primaryWindow: AgentQuotaWindow? {
        windows.first(where: { $0.kind == "rolling_short" }) ?? windows.first(where: { $0.kind == "weekly" }) ?? windows.first
    }

    public var weeklyWindow: AgentQuotaWindow? {
        windows.first(where: { $0.kind == "weekly" })
    }

    public var hasData: Bool {
        primaryWindow != nil || weeklyWindow != nil || credits != nil
    }

    public var providerDisplayName: String {
        switch provider {
        case "codex": "Codex / ChatGPT"
        case "claude_code": "Claude Code"
        case "antigravity": "Antigravity"
        case "grok": "Grok"
        case "zai": "Z.ai GLM"
        case "deepseek": "DeepSeek"
        case "devin": "Devin"
        case "moonshot": "Moonshot"
        default: scopeLabel.isEmpty ? provider.capitalized : scopeLabel
        }
    }

    public static func homePlaceholder(provider: String) -> AgentQuotaProviderItem {
        AgentQuotaProviderItem(
            provider: provider, scopeId: "home-placeholder", scopeLabel: "", status: "unavailable",
            planName: nil, emailMasked: nil, windows: [], credits: nil, currency: nil,
            isStale: false, dataTimestamp: nil, lastErrorMessage: nil)
    }

    /// 固定の 6 プロバイダー (データが無ければプレースホルダ) + それ以外、の順に並べる。
    public static func displayOrder(_ providers: [AgentQuotaProviderItem]) -> [AgentQuotaProviderItem] {
        let fixed = homeProviderIDs.map { provider in
            providers
                .filter { $0.provider == provider }
                .sorted { $0.scopeLabel < $1.scopeLabel }
                .first ?? .homePlaceholder(provider: provider)
        }
        let extras = providers
            .filter { !homeProviderIDs.contains($0.provider) }
            .sorted { a, b in
                let idxA = additionalProviderOrder.firstIndex(of: a.provider) ?? 99
                let idxB = additionalProviderOrder.firstIndex(of: b.provider) ?? 99
                if idxA == idxB { return a.scopeLabel < b.scopeLabel }
                return idxA < idxB
            }
        return fixed + extras
    }
}

/// 残量の色の段階 (SuperNotch と同じ)。バーやリングは分割せず、色だけをこの段階で変える。
public enum QuotaLevel: Int, Sendable, Comparable, CaseIterable {
    case limited  // 紫: 実質 0% (制限中)
    case critical  // 赤
    case low  // オレンジ
    case caution  // 黄
    case ok  // 緑

    public static func < (lhs: QuotaLevel, rhs: QuotaLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 5 時間枠 (など短い枠) は残り 10% / 20% / 30% で段階を切り替える。
    public static let shortWindowThresholds: [Double] = [10, 20, 30]
    /// 週次枠は 100% を 7 等分し、下から 3 区間を赤・オレンジ・黄にする (1 日分ずつ)。
    public static let weeklyThresholds: [Double] = [100.0 / 7, 200.0 / 7, 300.0 / 7]
    /// これ未満は制限中とみなす。
    public static let limitedThreshold = 0.5

    public init(remainingPct: Double, weekly: Bool) {
        let thresholds = weekly ? Self.weeklyThresholds : Self.shortWindowThresholds
        if remainingPct < Self.limitedThreshold {
            self = .limited
        } else if remainingPct < thresholds[0] {
            self = .critical
        } else if remainingPct < thresholds[1] {
            self = .low
        } else if remainingPct < thresholds[2] {
            self = .caution
        } else {
            self = .ok
        }
    }
}

extension AgentQuotaWindow {
    /// 週次枠か。`kind` が weekly のもの、または長さが 7 日以上のもの (モデル別の週次枠など)。
    public var isWeekly: Bool {
        kind == "weekly" || (windowMinutes ?? 0) >= 7 * 24 * 60
    }

    public var level: QuotaLevel {
        QuotaLevel(remainingPct: remainingPct, weekly: isWeekly)
    }
}

/// `/api/v1/quota` のデコード。
public enum AgentQuotaPayload {
    public static func decode(_ data: Data) throws -> [AgentQuotaProviderItem] {
        struct WindowRaw: Decodable {
            let id: String
            let label: String
            let kind: String
            let used_pct: Double?
            let remaining_pct: Double?
            let window_minutes: Int?
            let resets_at: String?
            let resets_in_seconds: Int?
        }
        struct CreditsRaw: Decodable {
            let currency: String?
            let remaining_amount: Double?
        }
        struct AccountRaw: Decodable {
            let plan_name: String?
            let email_masked: String?
        }
        struct ErrorRaw: Decodable {
            let code: String?
            let message: String?
        }
        struct ProviderRaw: Decodable {
            let provider: String
            let scope_id: String
            let scope_label: String?
            let status: String
            let account: AccountRaw?
            let windows: [WindowRaw]?
            let credits: CreditsRaw?
            let fetched_at: String?
            let last_success_at: String?
            let is_stale: Bool?
            let last_error: ErrorRaw?
        }
        struct QuotaPayload: Decodable {
            let providers: [ProviderRaw]
        }

        let payload = try JSONDecoder().decode(QuotaPayload.self, from: data)
        return payload.providers.compactMap { raw in
            let wins = (raw.windows ?? []).map { w in
                AgentQuotaWindow(
                    id: w.id, label: w.label, kind: w.kind,
                    usedPct: w.used_pct ?? 0.0,
                    remainingPct: w.remaining_pct ?? 100.0,
                    windowMinutes: w.window_minutes,
                    resetsAt: parseTimestamp(w.resets_at),
                    resetsInSeconds: w.resets_in_seconds)
            }
            if wins.isEmpty && raw.credits?.remaining_amount == nil && raw.status == "unavailable" {
                return nil
            }
            return AgentQuotaProviderItem(
                provider: raw.provider,
                scopeId: raw.scope_id,
                scopeLabel: raw.scope_label ?? raw.provider,
                status: raw.status,
                planName: raw.account?.plan_name,
                emailMasked: raw.account?.email_masked,
                windows: wins,
                credits: raw.credits?.remaining_amount,
                currency: raw.credits?.currency,
                isStale: raw.is_stale ?? false,
                dataTimestamp: parseTimestamp(raw.last_success_at) ?? parseTimestamp(raw.fetched_at),
                lastErrorMessage: raw.last_error?.message)
        }
    }

    /// "…48.392364Z" と "…48Z" の両方を受け付ける。
    public static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public enum AgentQuotaDisplay {
    /// 一時的な取得失敗でホームを騒がせない。キャッシュが 10 分変わらなかったときだけ古いと出す。
    public static let staleDisplayThreshold: TimeInterval = 10 * 60

    public static func resetSeconds(for window: AgentQuotaWindow?, now: Date) -> Int? {
        guard let window else { return nil }
        if let resetsAt = window.resetsAt {
            return max(0, Int(ceil(resetsAt.timeIntervalSince(now))))
        }
        return window.resetsInSeconds.map { max(0, $0) }
    }

    public static func resetLabel(for window: AgentQuotaWindow?, now: Date) -> String? {
        guard let window else { return nil }

        let seconds: Int
        if let resetsAt = window.resetsAt {
            seconds = max(0, Int(ceil(resetsAt.timeIntervalSince(now))))
        } else if let resetsInSeconds = window.resetsInSeconds {
            seconds = max(0, resetsInSeconds)
        } else if window.remainingPct >= 100 || window.usedPct <= 0,
            let windowMinutes = window.windowMinutes,
            windowMinutes > 0
        {
            seconds = windowMinutes * 60
        } else {
            return nil
        }

        return duration(seconds: seconds)
    }

    public static func ageLabel(for timestamp: Date?, now: Date) -> String? {
        guard let timestamp else { return nil }
        let age = max(0, Int(now.timeIntervalSince(timestamp)))
        if age < 5 { return "Updated just now" }
        return "Updated \(duration(seconds: age)) ago"
    }

    public static func shouldShowStaleState(isStale: Bool, timestamp: Date?, now: Date) -> Bool {
        guard isStale, let timestamp else { return false }
        return now.timeIntervalSince(timestamp) >= staleDisplayThreshold
    }

    public static func duration(seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds == 0 { return "now" }
        if seconds < 60 { return "\(seconds)s" }

        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 {
            let remainingHours = hours % 24
            return remainingHours > 0 ? "\(days)d\(remainingHours)h" : "\(days)d"
        }
        if hours > 0 {
            let remainingMinutes = minutes % 60
            return remainingMinutes > 0 ? "\(hours)h\(remainingMinutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}
