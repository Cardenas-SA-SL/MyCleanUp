import Foundation

enum HealthLevel: Equatable {
    case good
    case warning
    case critical
}

enum HealthAssessor {
    private static let gigabyte: Int64 = 1_073_741_824

    static func disk(freeFraction: Double, freeBytes: Int64) -> HealthLevel {
        if freeFraction < 0.08 || freeBytes < 15 * gigabyte { return .critical }
        if freeFraction < 0.20 || freeBytes < 40 * gigabyte { return .warning }
        return .good
    }

    static func memory(availableFraction: Double) -> HealthLevel {
        if availableFraction < 0.10 { return .critical }
        if availableFraction < 0.25 { return .warning }
        return .good
    }

    static func battery(percent: Int, isCharging: Bool) -> HealthLevel {
        if isCharging || percent > 40 { return .good }
        if percent <= 20 { return .critical }
        return .warning
    }

    static func cpuLoad(_ load: Double) -> HealthLevel {
        if load > 0.85 { return .critical }
        if load > 0.60 { return .warning }
        return .good
    }

    static func cpuTemperature(_ celsius: Double) -> HealthLevel {
        if celsius >= 90 { return .critical }
        if celsius >= 75 { return .warning }
        return .good
    }

    static func batteryTemperature(_ celsius: Double) -> HealthLevel {
        if celsius >= 45 { return .critical }
        if celsius >= 40 { return .warning }
        return .good
    }

    static func junk(bytes: Int64) -> HealthLevel {
        if bytes >= 5 * gigabyte { return .critical }
        if bytes >= gigabyte { return .warning }
        return .good
    }
}
