import Foundation

final class Throttler: @unchecked Sendable {
    private let interval: TimeInterval
    private var last = Date.distantPast
    private let lock = NSLock()

    init(_ interval: TimeInterval) { self.interval = interval }

    func allow() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(last) >= interval else { return false }
        last = now
        return true
    }
}
