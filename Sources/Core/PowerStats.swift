import Foundation
import IOKit.ps

struct BatteryStats {
    let hasBattery: Bool
    let percent: Int
    let isCharging: Bool
    let onACPower: Bool
    let minutesRemaining: Int?
}

enum PowerStats {
    static func battery() -> BatteryStats {
        let empty = BatteryStats(hasBattery: false, percent: 0, isCharging: false,
                                 onACPower: false, minutesRemaining: nil)
        guard let infoReference = IOPSCopyPowerSourcesInfo() else { return empty }
        let info = infoReference.takeRetainedValue()
        guard let listReference = IOPSCopyPowerSourcesList(info) else { return empty }
        let sources = listReference.takeRetainedValue() as Array

        for source in sources {
            guard let descriptionReference = IOPSGetPowerSourceDescription(info, source) else { continue }
            let description = descriptionReference.takeUnretainedValue() as NSDictionary
            guard (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let rawPercent = maximum.isFinite && maximum > 0 && current.isFinite
                ? current / maximum * 100
                : 0
            let percent = rawPercent.isFinite ? Int(min(100, max(0, rawPercent)).rounded()) : 0
            let charging = (description[kIOPSIsChargingKey] as? NSNumber)?.boolValue ?? false
            let powerSourceState = description[kIOPSPowerSourceStateKey] as? String
            let onACPower = powerSourceState == kIOPSACPowerValue
            let rawMinutes = (description[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue ?? -1
            let minutes = charging || rawMinutes <= 0 ? nil : rawMinutes
            return BatteryStats(hasBattery: true, percent: min(100, max(0, percent)),
                                isCharging: charging, onACPower: onACPower,
                                minutesRemaining: minutes)
        }
        return empty
    }
}
