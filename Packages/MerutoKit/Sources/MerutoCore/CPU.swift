/// CPU 使用率 (0...1)。
public struct CPUUsage: Sendable, Equatable, Codable {
    public var user: Double
    public var system: Double

    public init(user: Double, system: Double) {
        self.user = user
        self.system = system
    }

    public var total: Double { min(1, max(0, user + system)) }
}

/// `host_statistics(HOST_CPU_LOAD_INFO)` / `host_processor_info` の累積 tick。カーネル側は 32bit で一周する。
public struct CPUTicks: Sendable, Equatable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    /// 2点間の使用率。一周しても `&-` で正しい差分になる。経過 tick が 0 なら nil。
    public static func usage(from old: CPUTicks, to new: CPUTicks) -> CPUUsage? {
        let user = Double(new.user &- old.user) + Double(new.nice &- old.nice)
        let system = Double(new.system &- old.system)
        let idle = Double(new.idle &- old.idle)
        let total = user + system + idle
        guard total > 0 else { return nil }
        return CPUUsage(user: user / total, system: system / total)
    }
}

/// 全体とコアごとの使用率。
public struct CPUSample: Sendable, Equatable {
    public var total: CPUUsage
    public var cores: [Double]

    public init(total: CPUUsage, cores: [Double]) {
        self.total = total
        self.cores = cores
    }
}
