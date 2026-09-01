import Foundation
import Darwin
import IOKit

struct Temperatures {
    let cpuCelsius: Double?
    let batteryCelsius: Double?
}

enum ThermalStats {
    static func read() -> Temperatures {
        let battery = readBatteryTemperature()
        let cpu = HIDTemperatureReader.shared?.readCPUTemperature()
        return Temperatures(cpuCelsius: cpu, batteryCelsius: battery)
    }

    private static func readBatteryTemperature() -> Double? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "Temperature" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else { return nil }
        let celsius = property.doubleValue / 100
        guard celsius.isFinite, (0...80).contains(celsius) else { return nil }
        return celsius
    }
}

private final class HIDTemperatureReader {
    typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Void
    typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    typealias CopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    typealias GetFloatValue = @convention(c) (CFTypeRef, Int32) -> Double

    static let shared = HIDTemperatureReader()

    private let libraryHandle: UnsafeMutableRawPointer
    private let client: CFTypeRef
    private let copyServices: CopyServices
    private let copyProperty: CopyProperty
    private let copyEvent: CopyEvent
    private let getFloatValue: GetFloatValue
    private let lock = NSLock()

    private init?() {
        let path = "/System/Library/Frameworks/IOKit.framework/IOKit"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL),
              let create: CreateClient = Self.symbol("IOHIDEventSystemClientCreate", in: handle),
              let setMatching: SetMatching = Self.symbol("IOHIDEventSystemClientSetMatching", in: handle),
              let copyServices: CopyServices = Self.symbol("IOHIDEventSystemClientCopyServices", in: handle),
              let copyProperty: CopyProperty = Self.symbol("IOHIDServiceClientCopyProperty", in: handle),
              let copyEvent: CopyEvent = Self.symbol("IOHIDServiceClientCopyEvent", in: handle),
              let getFloatValue: GetFloatValue = Self.symbol("IOHIDEventGetFloatValue", in: handle),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else {
            return nil
        }

        let matching = [
            "PrimaryUsagePage": NSNumber(value: 0xff00),
            "PrimaryUsage": NSNumber(value: 5)
        ] as CFDictionary
        setMatching(client, matching)

        libraryHandle = handle
        self.client = client
        self.copyServices = copyServices
        self.copyProperty = copyProperty
        self.copyEvent = copyEvent
        self.getFloatValue = getFloatValue
    }

    func readCPUTemperature() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let services = copyServices(client)?.takeRetainedValue(),
              CFArrayGetCount(services) > 0 else { return nil }

        var dieValues: [Double] = []
        var socValues: [Double] = []
        for index in 0..<CFArrayGetCount(services) {
            guard let rawService = CFArrayGetValueAtIndex(services, index) else { continue }
            let service = unsafeBitCast(rawService, to: CFTypeRef.self)
            guard let property = copyProperty(service, "Product" as CFString)?.takeRetainedValue(),
                  let product = property as? String,
                  let event = copyEvent(service, 15, 0, 0)?.takeRetainedValue() else { continue }
            let value = getFloatValue(event, Int32(15 << 16))
            guard value.isFinite, (1...125).contains(value) else { continue }
            let name = product.lowercased()
            if name.contains("tdie") { dieValues.append(value) }
            else if name.contains("soc") { socValues.append(value) }
        }
        return dieValues.max() ?? socValues.max()
    }

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
