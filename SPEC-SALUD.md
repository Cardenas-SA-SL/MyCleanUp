# MyCleanUp - Addendum v1.3: reapertura como app normal + semáforo de salud

Two features. All prior constraints apply (fixed scripts untouched, Spanish UI, no em dash, macOS 13 APIs, no GUI launch, NO git commands).

## A. Reopen the main window when the app icon is clicked

Problem: with the window closed, the app lives in the menu bar; clicking its icon in Dock/Apps/Launchpad only activates it and no window appears. It must behave like any desktop app.

- In the existing AppDelegate implement `applicationShouldHandleReopen(_:hasVisibleWindows:)`: when there are no visible windows, reopen the main window; when there are, bring the key/titled one to front. Also deminiaturize if minimized.
- Mechanism to reopen from the delegate: give AppState an optional closure `openMainWindow: (() -> Void)?` plus a weak static reference (e.g. `static private(set) weak var current: AppState?` set in init). ContentView sets `appState.openMainWindow = { openWindow(id: "main") }` in .onAppear (capturing the `@Environment(\.openWindow)` action). The delegate calls `AppState.current?.openMainWindow?()` and falls back to ordering front any titled window in NSApp.windows. Always `NSApp.activate(ignoringOtherApps: true)`.
- The gear item "Abrir MyCleanUp" and the popover buttons should route through the same path so behavior stays consistent.

## B. Health colors (user request: "marca en colores lo que está bien y lo que está alterado o en riesgo")

### Core: HealthAssessor.swift (new, pure and testable)
```swift
enum HealthLevel { case good, warning, critical }
enum HealthAssessor {
    static func disk(freeFraction: Double, freeBytes: Int64) -> HealthLevel
    // critical: freeFraction < 0.08 or freeBytes < 15 GB; warning: < 0.20 or < 40 GB; else good
    static func memory(availableFraction: Double) -> HealthLevel
    // critical < 0.10; warning < 0.25; else good
    static func battery(percent: Int, isCharging: Bool) -> HealthLevel
    // charging or percent > 40 -> good; percent <= 20 -> critical; else warning
    static func cpuLoad(_ load: Double) -> HealthLevel        // critical > 0.85; warning > 0.60
    static func cpuTemperature(_ celsius: Double) -> HealthLevel      // critical >= 90; warning >= 75
    static func batteryTemperature(_ celsius: Double) -> HealthLevel  // critical >= 45; warning >= 40
    static func junk(bytes: Int64) -> HealthLevel             // critical >= 5 GB; warning >= 1 GB
}
```
(GB = 1_073_741_824. Guard division by zero upstream.)

### Popover (MenuBarView) on the violet background
Color the VALUE line of each card by its level (good soft mint #7BE3A6, warning amber #FFC978, critical soft red #FF8A80; define once in a helper, e.g. `func healthColor(_ level: HealthLevel) -> Color`):
- Disco: the "X libres" line by `disk(...)`.
- Memoria: the "X disponibles" line and the usage bar fill by `memory(availableFraction: available/total)`.
- Batería: the "NN %" line by `battery(...)`; the caption keeps its muted color unless `batteryTemperature` is warning/critical, then color the caption with that level.
- CPU: the "Carga: NN %" line by `cpuLoad`; caption colored by `cpuTemperature` when warning/critical, else muted.
- Red: keep white (no health semantics).
- Footer junk text: colored by `junk(bytes:)` when a scan is done (good state keeps white).

### Dashboard (adaptive colors: system .green/.orange/.red)
- Disco card: value text colored by disk level.
- Memoria card: value text and ProgressView tint by memory level (replaces the current 0.85 orange rule).
- Junk summary card: the "X de basura encontrada" title colored by junk level (only when scan done).
- Trash card unchanged.

## Tests (Tests/smoke.swift)
Add pure assertions for HealthAssessor covering each function's three bands (at least 10 checks total, e.g. disk critical at 5 percent free, battery good when charging at 15 percent, cpu warning at 0.7, junk critical at 6 GB...). All existing tests must keep passing; run ./scripts/test.sh until ALL TESTS PASSED and ./scripts/build.sh until success.
