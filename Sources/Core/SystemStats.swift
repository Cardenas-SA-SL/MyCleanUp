import Foundation

struct DiskStats {
    let total: Int64
    let free: Int64
    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}

struct MemoryStats {
    let total: Int64
    let used: Int64
    var fraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}

enum SystemStats {
    static func disk() -> DiskStats? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskStats(total: Int64(total), free: free)
    }

    static func memory() -> MemoryStats {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return MemoryStats(total: total, used: 0) }
        let pages = UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let used = min(UInt64(total), pages * UInt64(vm_page_size))
        return MemoryStats(total: total, used: Int64(used))
    }
}
