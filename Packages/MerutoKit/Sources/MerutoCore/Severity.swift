import Foundation

/// メーターの色分けの段階。
public enum Severity: Int, Sendable, Equatable, Comparable, Codable {
    case normal
    case warning
    case serious
    case critical

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 使用率(0...1)を段階に変換するしきい値。
public struct UsageThresholds: Sendable, Equatable {
    public var warning: Double
    public var critical: Double

    public static let standard = UsageThresholds(warning: 0.60, critical: 0.85)

    public init(warning: Double, critical: Double) {
        self.warning = warning
        self.critical = critical
    }

    public func severity(for value: Double) -> Severity {
        if value >= critical { return .critical }
        if value >= warning { return .warning }
        return .normal
    }
}

/// `ProcessInfo.ThermalState` を OS に依存せず持ち回すための写し。
public enum ThermalLevel: Int, Sendable, Codable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical

    public var severity: Severity {
        switch self {
        case .nominal: .normal
        case .fair: .warning
        case .serious: .serious
        case .critical: .critical
        }
    }

    public var label: String {
        switch self {
        case .nominal: "正常"
        case .fair: "やや高温"
        case .serious: "高温"
        case .critical: "危険"
        }
    }

    public var englishLabel: String {
        switch self {
        case .nominal: "NOMINAL"
        case .fair: "FAIR"
        case .serious: "SERIOUS"
        case .critical: "CRITICAL"
        }
    }
}

/// 電池の状態。
public enum ChargeState: String, Sendable, Codable {
    case unknown
    case unplugged
    case charging
    case full

    public var label: String {
        switch self {
        case .unknown: "不明"
        case .unplugged: "バッテリー駆動"
        case .charging: "充電中"
        case .full: "充電完了"
        }
    }
}

public func batterySeverity(level: Double?, state: ChargeState) -> Severity {
    guard state == .unplugged, let level else { return .normal }
    if level <= 0.10 { return .critical }
    if level <= 0.20 { return .warning }
    return .normal
}
