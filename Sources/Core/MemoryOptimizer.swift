import Foundation
import Darwin

struct MemoryPressureSnapshot {
    let free: Int64
    let active: Int64
    let inactive: Int64
    let speculative: Int64
    let wired: Int64
    let compressed: Int64
    let total: Int64

    var available: Int64 { MemoryOptimizer.saturatingAdd(max(0, free), max(0, inactive)) }
    var used: Int64 {
        MemoryOptimizer.saturatingAdd(MemoryOptimizer.saturatingAdd(max(0, active), max(0, wired)),
                                      max(0, compressed))
    }
}

struct OptimizeResult {
    let before: MemoryPressureSnapshot
    let after: MemoryPressureSnapshot
    let freedBytes: Int64
    let duration: TimeInterval
}

enum MemoryOptimizer {
    static func snapshot() -> MemoryPressureSnapshot {
        let total = Int64(clamping: ProcessInfo.processInfo.physicalMemory)
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemoryPressureSnapshot(free: 0, active: 0, inactive: 0, speculative: 0,
                                          wired: 0, compressed: 0, total: total)
        }
        let pageSize = Int64(clamping: vm_page_size)
        func bytes(_ pages: natural_t) -> Int64 {
            guard pageSize > 0 else { return 0 }
            let count = Int64(pages)
            return count > Int64.max / pageSize ? Int64.max : count * pageSize
        }
        return MemoryPressureSnapshot(
            free: bytes(info.free_count),
            active: bytes(info.active_count),
            inactive: bytes(info.inactive_count),
            speculative: bytes(info.speculative_count),
            wired: bytes(info.wire_count),
            compressed: bytes(info.compressor_page_count),
            total: total
        )
    }

    static func plannedAllocation(for snapshot: MemoryPressureSnapshot, maxBytes: Int64) -> Int64 {
        guard maxBytes > 0, snapshot.total > 0 else { return 0 }
        let inactive = max(0, snapshot.inactive)
        let speculative = max(0, snapshot.speculative)
        let halfFree = max(0, snapshot.free) / 2
        let reclaimable = saturatingAdd(saturatingAdd(inactive, speculative), halfFree)
        return max(0, min(reclaimable, snapshot.total / 2, maxBytes))
    }

    static func hasMemoryPressure(_ snapshot: MemoryPressureSnapshot) -> Bool {
        guard snapshot.total > 0 else { return false }
        let threshold = snapshot.total / 4
        return snapshot.available < threshold || max(0, snapshot.compressed) > threshold
    }

    static func optimize(maxBytes: Int64 = 1 << 62,
                         timeLimit: TimeInterval = 15,
                         progress: ((Int64) -> Void)? = nil) -> OptimizeResult {
        let started = Date()
        let before = snapshot()
        guard hasMemoryPressure(before) else {
            return OptimizeResult(before: before, after: before, freedBytes: 0,
                                  duration: Date().timeIntervalSince(started))
        }
        let planned = plannedAllocation(for: before, maxBytes: maxBytes)
        let chunkSize: Int64 = 64 * 1_048_576
        let checkInterval: Int64 = 256 * 1_048_576
        let minimumFree: Int64 = 400 * 1_048_576
        var allocations: [UnsafeMutableRawPointer] = []
        var allocated: Int64 = 0
        var nextCheck = checkInterval

        while allocated < planned && Date().timeIntervalSince(started) <= timeLimit {
            let requested = min(chunkSize, planned - allocated)
            guard requested > 0, let pointer = malloc(Int(requested)) else { break }
            memset(pointer, 0xA5, Int(requested))
            allocations.append(pointer)
            allocated += requested
            progress?(allocated)

            if allocated >= nextCheck {
                let current = snapshot()
                if current.free < minimumFree || Date().timeIntervalSince(started) > timeLimit { break }
                nextCheck += checkInterval
            }
        }

        for pointer in allocations { free(pointer) }
        usleep(300_000)
        let after = snapshot()
        return OptimizeResult(
            before: before,
            after: after,
            freedBytes: after.available >= before.available ? after.available - before.available : 0,
            duration: Date().timeIntervalSince(started)
        )
    }

    static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        if overflow { return rhs >= 0 ? Int64.max : Int64.min }
        return sum
    }
}
