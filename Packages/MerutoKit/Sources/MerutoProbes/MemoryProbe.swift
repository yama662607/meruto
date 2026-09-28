import Darwin
import Foundation

/// 物理メモリの内訳。Activity Monitor と同じ考え方で App = internal - purgeable、
/// キャッシュ = external + purgeable とし、使用中 = App + Wired + 圧縮。
public struct MemoryUsage: Sendable, Equatable {
    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    /// このアプリ自身のフットプリント。
    public var ownFootprint: UInt64?

    public var used: UInt64 { app + wired + compressed }
    public var usedFraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}

public final class MemoryProbe: @unchecked Sendable {
    private let total = ProcessInfo.processInfo.physicalMemory
    private let pageSize: UInt64

    public init() {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        pageSize = UInt64(size)
    }

    public func sample() -> MemoryUsage? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, total > 0 else { return nil }

        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = internalPages > purgeable ? internalPages - purgeable : 0
        return MemoryUsage(
            total: total,
            app: app * pageSize,
            wired: UInt64(stats.wire_count) * pageSize,
            compressed: UInt64(stats.compressor_page_count) * pageSize,
            cached: (UInt64(stats.external_page_count) + purgeable) * pageSize,
            ownFootprint: Self.ownFootprint())
    }

    static func ownFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil
    }
}
