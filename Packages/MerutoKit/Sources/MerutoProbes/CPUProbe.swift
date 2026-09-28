import Darwin
import MerutoCore

/// 全体とコアごとの CPU 使用率。前回の tick との差分で求めるので初回は nil。
/// iOS でも `host_processor_info` はサンドボックス内から読める。
public final class CPUProbe: @unchecked Sendable {
    private var lastCores: [CPUTicks]?

    public init() {}

    public func sample() -> CPUSample? {
        guard let now = Self.readCoreTicks(), !now.isEmpty else { return nil }
        defer { lastCores = now }
        guard let last = lastCores, last.count == now.count else { return nil }

        var cores: [Double] = []
        var sumOld = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        var sumNew = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        for (old, new) in zip(last, now) {
            cores.append(CPUTicks.usage(from: old, to: new)?.total ?? 0)
            sumOld.user &+= old.user
            sumOld.system &+= old.system
            sumOld.idle &+= old.idle
            sumOld.nice &+= old.nice
            sumNew.user &+= new.user
            sumNew.system &+= new.system
            sumNew.idle &+= new.idle
            sumNew.nice &+= new.nice
        }
        guard let total = CPUTicks.usage(from: sumOld, to: sumNew) else { return nil }
        return CPUSample(total: total, cores: cores)
    }

    static func readCoreTicks() -> [CPUTicks]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_, vm_address_t(bitPattern: info),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { core in
            let base = core * states
            return CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
        }
    }
}
