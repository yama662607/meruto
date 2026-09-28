import Darwin
import Foundation

/// 変わらない (または滅多に変わらない) 端末情報。
public struct SystemInfo: Sendable, Equatable {
    /// "iPhone17,1" のような機種 ID。シミュレータでは模擬している機種の ID。
    public var modelIdentifier: String
    public var logicalCores: Int
    public var performanceCores: Int?
    public var efficiencyCores: Int?
    public var physicalMemory: UInt64
    public var osVersion: String
    public var bootDate: Date?

    public static func read() -> SystemInfo {
        let env = ProcessInfo.processInfo.environment
        let model = env["SIMULATOR_MODEL_IDENTIFIER"] ?? sysctlString("hw.machine") ?? "Unknown"
        let levels = sysctlInt("hw.nperflevels") ?? 0
        let bootDate: Date? = {
            var tv = timeval()
            var size = MemoryLayout<timeval>.size
            guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1e6)
        }()
        return SystemInfo(
            modelIdentifier: model,
            logicalCores: ProcessInfo.processInfo.activeProcessorCount,
            performanceCores: levels >= 1 ? sysctlInt("hw.perflevel0.logicalcpu") : nil,
            efficiencyCores: levels >= 2 ? sysctlInt("hw.perflevel1.logicalcpu") : nil,
            physicalMemory: ProcessInfo.processInfo.physicalMemory,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            bootDate: bootDate)
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

/// ストレージ容量。「重要な用途で使える空き」は iOS がパージ可能なキャッシュを含めた値。
public struct StorageUsage: Sendable, Equatable {
    public var total: UInt64
    public var available: UInt64

    public var used: UInt64 { total > available ? total - available : 0 }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public static func read() -> StorageUsage? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
            ]),
            let total = values.volumeTotalCapacity
        else { return nil }
        let important = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
        let plain = values.volumeAvailableCapacity.map { UInt64(max(0, $0)) }
        guard let available = important ?? plain else { return nil }
        return StorageUsage(total: UInt64(total), available: available)
    }
}
