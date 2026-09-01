import Foundation
import Darwin

final class NetRateSampler {
    private var previousUp: UInt64?
    private var previousDown: UInt64?
    private var previousDate: Date?

    init() {}

    func sample() -> (up: Int64, down: Int64) {
        let totals = byteTotals()
        let now = Date()
        guard let oldUp = previousUp, let oldDown = previousDown, let oldDate = previousDate else {
            previousUp = totals.up
            previousDown = totals.down
            previousDate = now
            return (0, 0)
        }
        previousUp = totals.up
        previousDown = totals.down
        previousDate = now
        let elapsed = now.timeIntervalSince(oldDate)
        guard elapsed.isFinite, elapsed > 0 else { return (0, 0) }
        let upDelta = totals.up >= oldUp ? totals.up - oldUp : 0
        let downDelta = totals.down >= oldDown ? totals.down - oldDown : 0
        return (safeRate(delta: upDelta, elapsed: elapsed), safeRate(delta: downDelta, elapsed: elapsed))
    }

    private func byteTotals() -> (up: UInt64, down: UInt64) {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let start = first else { return (0, 0) }
        defer { freeifaddrs(first) }
        var up: UInt64 = 0
        var down: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = start
        while let address = current {
            let interface = address.pointee
            let name = String(cString: interface.ifa_name)
            let flags = UInt32(interface.ifa_flags)
            if name.hasPrefix("en"), flags & UInt32(IFF_LOOPBACK) == 0, let rawData = interface.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                up = saturatingAdd(up, UInt64(clamping: data.ifi_obytes))
                down = saturatingAdd(down, UInt64(clamping: data.ifi_ibytes))
            }
            current = interface.ifa_next
        }
        return (up, down)
    }

    private func safeRate(delta: UInt64, elapsed: TimeInterval) -> Int64 {
        let rate = Double(delta) / elapsed
        guard rate.isFinite else { return rate > 0 ? Int64.max : 0 }
        guard rate > 0 else { return 0 }
        if rate >= Double(Int64.max) { return Int64.max }
        return Int64(rate.rounded(.down))
    }

    private func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }
}
