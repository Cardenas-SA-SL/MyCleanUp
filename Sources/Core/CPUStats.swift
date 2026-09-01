import Foundation
import Darwin

final class CPULoadSampler {
    private var previousActive: UInt64?
    private var previousTotal: UInt64?
    var coreCount: Int { ProcessInfo.processInfo.activeProcessorCount }

    init() {}

    func sample() -> Double {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }

        let statesPerCPU = Int(CPU_STATE_MAX)
        let availableValues = Int(infoCount)
        guard statesPerCPU > 0, Int(cpuCount) <= availableValues / statesPerCPU else { return 0 }
        var active: UInt64 = 0
        var total: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let offset = cpu * statesPerCPU
            let user = Self.unsignedTick(info[offset + Int(CPU_STATE_USER)])
            let system = Self.unsignedTick(info[offset + Int(CPU_STATE_SYSTEM)])
            let nice = Self.unsignedTick(info[offset + Int(CPU_STATE_NICE)])
            let idle = Self.unsignedTick(info[offset + Int(CPU_STATE_IDLE)])
            active = Self.saturatingAdd(active, user)
            active = Self.saturatingAdd(active, system)
            active = Self.saturatingAdd(active, nice)
            total = Self.saturatingAdd(total, user)
            total = Self.saturatingAdd(total, system)
            total = Self.saturatingAdd(total, nice)
            total = Self.saturatingAdd(total, idle)
        }

        guard let oldActive = previousActive, let oldTotal = previousTotal else {
            previousActive = active
            previousTotal = total
            return 0
        }
        previousActive = active
        previousTotal = total
        let activeDelta = Self.clampedDelta(current: active, previous: oldActive)
        let totalDelta = Self.clampedDelta(current: total, previous: oldTotal)
        guard totalDelta > 0 else { return 0 }
        return min(1, max(0, Double(activeDelta) / Double(totalDelta)))
    }

    static func unsignedTick(_ value: integer_t) -> UInt64 {
        UInt64(UInt32(bitPattern: value))
    }

    private static func clampedDelta(current: UInt64, previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    private static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }
}
