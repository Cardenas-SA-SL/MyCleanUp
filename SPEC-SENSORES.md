# MyCleanUp - Addendum v1.2: temperaturas de CPU y batería

Add CPU and battery temperature to the menu bar popover. All constraints from SPEC.md still apply (macOS 13, swiftc only, fixed scripts untouched, Spanish UI, no em dash U+2014, graceful degradation, no root, no network).

## New Core file: ThermalStats.swift

```swift
struct Temperatures { let cpuCelsius: Double?; let batteryCelsius: Double? }
enum ThermalStats {
    static func read() -> Temperatures
}
```

### Battery temperature (public API, do this first)
Via IOKit registry: `IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))`, read property "Temperature" with `IORegistryEntryCreateCFProperty`; the value is an integer in hundredths of a degree Celsius (e.g. 3050 -> 30.50). Release the service object. Return nil when the service or property is missing (desktop Macs) or the value is outside 0...80.

### CPU temperature (Apple Silicon, HID sensor SPI via dlsym)
There is no public API; use the IOHIDEventSystemClient SPI that Stats/iStat/macmon use, resolved at runtime with dlopen/dlsym on "/System/Library/Frameworks/IOKit.framework/IOKit" so nothing is linked at build time and every failure degrades to nil:

- `IOHIDEventSystemClientCreate(CFAllocator?) -> Unmanaged<CFTypeRef>?`
- `IOHIDEventSystemClientSetMatching(client, CFDictionary) -> Void`
- `IOHIDEventSystemClientCopyServices(client) -> Unmanaged<CFArray>?`
- `IOHIDServiceClientCopyProperty(service, CFString) -> Unmanaged<CFTypeRef>?` with key "Product"
- `IOHIDServiceClientCopyEvent(service, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?`
- `IOHIDEventGetFloatValue(event, Int32) -> Double`

Constants: temperature event type = 15; field = 15 << 16. Matching dictionary: `{"PrimaryUsagePage": 0xff00, "PrimaryUsage": 5}` (Apple vendor sensor page, temperature usage).

Procedure: create the client ONCE and cache it (a small final class holding the function pointers and client); on each read, copy services (also cacheable), read each service's Product name and temperature event value; keep values in 1...125. CPU value = max over sensors whose lowercased name contains "tdie"; if none matched, fall back to sensors whose name contains "soc"; if still none, nil. Use @convention(c) typealiases for the dlsym pointers and correct Unmanaged retain/release discipline (Copy* results are +1: takeRetainedValue).

Everything must be defensive: any nil dlsym, nil client, empty array -> return nil temperature, never crash, never block (reads are cheap; no sleeps).

## Wiring

- `MenuBarModel`: add `@Published var temperatures = Temperatures(cpuCelsius: nil, batteryCelsius: nil)`; refresh it on the same 1.5 s tick (read ThermalStats in the detached background task like the other samplers).
- CPU card caption: when cpu temp known, "NN °C · N núcleos" (rounded Int); else keep "N núcleos".
- Battery card caption: append " · NN °C" when battery temp known (e.g. "Cargada · 31 °C").

## Tests (Tests/smoke.swift)

- `ThermalStats.read()` must not crash and must return within 2 seconds; when cpuCelsius is non-nil assert 1...125; when batteryCelsius is non-nil assert 0...80. IMPORTANT: inside a sandbox the HID event system and the battery service may be unavailable, so nil values are a PASS (print the skip in the label, e.g. "PASS temperaturas (cpu: n/d, bateria: 31.2)").
- Existing tests keep passing. Run ./scripts/test.sh until ALL TESTS PASSED and ./scripts/build.sh until success. Do not launch the GUI, no git.
