import Foundation

/// アプリとウィジェットで共有する置き場所。App Group が使えない署名 (個人チーム等) でも
/// 落ちないよう、取れなければアプリ自身の Application Support に退避する
/// (その場合ウィジェットとは共有されないが、ウィジェットは自力で取得できる値だけで描く)。
public enum SharedContainer {
    public static let appGroupID = "group.com.yama662607.meruto"

    public enum Key {
        public static let quotaBaseURL = "agentQuota.baseURL"
        public static let hapticGeiger = "wifi.hapticGeiger"
    }

    public enum File {
        public static let deviceSnapshot = "device-snapshot.json"
        public static let quotaPayload = "agent-quota.json"
        public static let quotaFetchedAt = "agent-quota.fetched-at"
        public static let surveys = "surveys.json"
    }

    /// Tailscale で公開した agent-quota (`tailscale serve --https=10000 http://127.0.0.1:8765`)。
    /// 値はビルド時に Config/Local.xcconfig の `AGENT_QUOTA_BASE_URL` から Info.plist へ入る。未設定なら空。
    public static var defaultQuotaBaseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "MerutoAgentQuotaBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public static var isAppGroupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    public static var directory: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Meruto", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    public static var defaults: UserDefaults {
        isAppGroupAvailable ? (UserDefaults(suiteName: appGroupID) ?? .standard) : .standard
    }

    public static var quotaBaseURL: String {
        get {
            let value = defaults.string(forKey: Key.quotaBaseURL)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value, !value.isEmpty else { return defaultQuotaBaseURL }
            return value
        }
        set { defaults.set(newValue, forKey: Key.quotaBaseURL) }
    }

    public static func url(for file: String) -> URL {
        directory.appendingPathComponent(file)
    }

    public static func read(_ file: String) -> Data? {
        try? Data(contentsOf: url(for: file))
    }

    public static func write(_ data: Data, to file: String) {
        try? data.write(to: url(for: file), options: .atomic)
    }

    public static func readJSON<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let data = read(file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    public static func writeJSON<T: Encodable>(_ value: T, to file: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        write(data, to: file)
    }
}
