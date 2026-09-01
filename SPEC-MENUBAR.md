# MyCleanUp - Addendum v1.1: Menu bar extra + RAM optimizer

Add a persistent menu bar presence (like CleanMyMac's) with a "Resumen del Mac" popover, plus a real RAM optimizer. All hard constraints from SPEC.md still apply (macOS 13 APIs, swiftc-only build via the FIXED scripts, Spanish UI, no em dash U+2014, public APIs only, no network).

## Menu bar scene

- In `Main.swift`, alongside the existing WindowGroup (give it `id: "main"`), add a `MenuBarExtra` with `.menuBarExtraStyle(.window)`. Label: SF Symbol "bubbles.and.sparkles" (falls back automatically); it must render as a template so it adapts to the menu bar.
- Both scenes share the SAME `AppState` instance.
- The status item lives while the app runs; closing the main window keeps the app (and the status item) alive (default SwiftUI behavior, do not add termination logic).

## Popover content: MenuBarView.swift (new, Sources/App)

Fixed width 360. Deliberate single-theme design: deep violet gradient background (darker variant of Theme.gradient, e.g. #3A2680 to #1E1440), white text, cards as white 8-10% translucent rounded 12 panels. This is a committed dark-violet look in both OS themes (paint everything explicitly).

Layout top to bottom:
1. Header: mini logo (16pt gradient rounded square with white sparkles) + "Resumen del Mac" headline white bold.
2. Grid 2 columns of stat cards (spacing 10):
   - **Disco**: icon "internaldrive.fill". "X libres" prominent + "de Y" caption. Trailing bottom button "Limpiar" (white capsule, violet text): opens the main window on the junk section and starts a scan if not scanned (see "Opening the main window" below).
   - **Memoria**: icon "memorychip.fill". "X disponibles" prominent (available = free + inactive pages) + thin usage bar. Button "Optimizar": runs the RAM optimizer inline; while running show small white spinner + "Optimizando..."; when done replace with result caption for ~8 s: "Se liberaron X" (or "Ya estaba optimizada" when freed < 32 MB).
   - **Batería** (hide the card entirely when the Mac has no battery): icon "battery.75". "NN %" prominent; caption "Cargando" when charging, else "Xh Ym restantes" when the estimate is known, else "En batería".
   - **CPU**: icon "cpu". "Carga: NN %" prominent, caption "N núcleos".
   - **Red**: icon "wifi". Two lines "↑ X/s" and "↓ Y/s" (per-second rates).
3. Footer bar separated by a subtle divider: sparkles icon + text: if a junk scan is done, "Limpia hasta TOTAL de basura" and clicking opens the main window on junk; otherwise a "Analizar basura" button-like row that opens the main window and starts the scan. Trailing: a gear `Menu` with items "Abrir MyCleanUp" (opens main window) and "Salir de MyCleanUp" (NSApp.terminate).

Behavior:
- Stats refresh: on appear refresh everything and start a 1.5 s timer (disk, memory, battery, CPU, network rates); stop the timer on disappear. CPU and network need two samples for a delta, so the first tick may show 0; that is fine.
- Opening the main window from the popover: use `@Environment(\.openWindow)` with `openWindow(id: "main")` plus `NSApp.activate(ignoringOtherApps: true)`; then set `appState.section` and trigger `appState.junk.scan()` if phase is idle.

## New Core files (Foundation/Darwin/IOKit only, no AppKit except where noted)

### MemoryOptimizer.swift
The real "liberar RAM" feature. Strategy (what memory cleaners do): briefly allocate and touch a large block of memory so the kernel evicts inactive/compressible pages, then release it.

```swift
struct MemoryPressureSnapshot { free, active, inactive, speculative, wired, compressed, total: Int64 }  // via host_statistics64
struct OptimizeResult { let before: MemoryPressureSnapshot; let after: MemoryPressureSnapshot; let freedBytes: Int64; let duration: TimeInterval }

enum MemoryOptimizer {
    static func snapshot() -> MemoryPressureSnapshot
    /// Pure and unit-testable: how much to allocate given a snapshot and caps.
    static func plannedAllocation(for s: MemoryPressureSnapshot, maxBytes: Int64) -> Int64
    static func optimize(maxBytes: Int64 = 1 << 62, timeLimit: TimeInterval = 15,
                         progress: ((Int64) -> Void)? = nil) -> OptimizeResult
}
```

- `plannedAllocation`: min(inactive + speculative + free/2, total/2, maxBytes), never negative.
- `optimize`: allocate 64 MB chunks (`malloc` + `memset` of the whole chunk to force committing); every 256 MB re-check a fresh snapshot and STOP EARLY if free < 400 MB or elapsed > timeLimit or allocated >= planned. Then free every chunk, usleep ~300 ms, take the after snapshot. `freedBytes = max(0, beforeUsed - afterUsed)` where used = active + wired + compressed. Must be crash-safe: handle malloc returning nil by stopping.
- Run at utility QoS from the caller; the function itself is synchronous.

### PowerStats.swift (import IOKit.ps)
```swift
struct BatteryStats { let hasBattery: Bool; let percent: Int; let isCharging: Bool; let minutesRemaining: Int? }
enum PowerStats { static func battery() -> BatteryStats }
```
Via `IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList` / `IOPSGetPowerSourceDescription` (keys kIOPSCurrentCapacityKey, kIOPSMaxCapacityKey, kIOPSIsChargingKey, kIOPSTimeToEmptyKey). minutesRemaining nil when unknown (-1) or charging.

### CPUStats.swift
```swift
final class CPULoadSampler {
    init()
    /// Overall load 0...1 since the previous call (first call returns 0).
    func sample() -> Double
    var coreCount: Int { get }
}
```
Via `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, summing user+system+nice deltas over total ticks delta across all CPUs; deallocate the vm buffer correctly with `vm_deallocate`.

### NetStats.swift
```swift
final class NetRateSampler {
    init()
    /// Bytes per second (up, down) since previous call; first call returns (0, 0).
    func sample() -> (up: Int64, down: Int64)
}
```
Via `getifaddrs`, summing `if_data.ifi_obytes` / `ifi_ibytes` over interfaces whose name starts with "en" (skip loopback/utun/awdl), delta divided by elapsed seconds. Handle counter wrap by clamping negatives to 0.

## App model wiring (Models.swift)

New `@MainActor final class MenuBarModel: ObservableObject` owned by AppState: published disk, memory snapshot/available, battery, cpuLoad, netUp/netDown, optimizer state (idle/running/result(OptimizeResult)); holds the CPULoadSampler and NetRateSampler instances; `startRefreshing()` / `stopRefreshing()` for the timer; `optimize()` runs MemoryOptimizer in a detached utility task with default caps and publishes the result, auto-clearing back to idle after ~8 s.

## Dashboard touch

In the Memoria stat card of DashboardView add a small "Optimizar" bordered button (controlSize .small) that runs the same optimizer through MenuBarModel (or a shared path) and, when finished, shows the freed amount as a caption for a few seconds and refreshes stats. Keep the card heights equal.

## Snapshot mode additions (Snapshot.swift)

After the current six captures and before terminating:
1. "07-menubar": create a temporary borderless NSWindow (360 x fitting height, transparent titlebar hidden) hosting MenuBarView via NSHostingView with the same AppState, order it front, wait 2.0 s (so CPU and net samplers tick at least once), capture it with the existing CGWindowListCreateImage capture (pass that window).
2. Trigger the optimizer through the same path the button uses, poll until it finishes (cap 45 s), wait 0.6 s, capture "08-menubar-optimizada" showing the result caption.
3. Also, right at the start of the run, if a status-bar window belonging to the app exists in `NSApp.windows` (the MenuBarExtra item), capture it as "00-icono-menubar" (tiny image proving the menu bar icon exists). Skip silently if not found.
Never leave the temporary window around: close it before terminate.

## Tests to add (Tests/smoke.swift)

- `plannedAllocation` bounds: never exceeds total/2 nor maxBytes; never negative even for a zeroed snapshot.
- A tiny real optimize run: `MemoryOptimizer.optimize(maxBytes: 128 * 1024 * 1024, timeLimit: 3)` completes, `freedBytes >= 0`, duration < 10 s.
- `PowerStats.battery()` returns percent in 0...100 when hasBattery.
- `CPULoadSampler`: two samples with ~200 ms in between; second sample in 0...1.
- `NetRateSampler`: two samples; values >= 0.
- Existing tests keep passing; ALL TESTS PASSED required, then ./scripts/build.sh must succeed. Do not modify the fixed scripts or Info.plist. Do not launch the GUI.
