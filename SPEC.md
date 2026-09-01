# MyCleanUp - Technical Specification v1.0

MyCleanUp is a native macOS disk cleanup utility in the spirit of CleanMyMac, for personal use on this Mac. It finds and removes system junk (caches, logs, dev caches), locates large files, uninstalls apps with their leftovers, and empties the Trash. UI is entirely in Spanish.

## Hard constraints

- Build system: plain `swiftc` from Command Line Tools. NO Xcode project, NO Swift Package Manager. The provided `scripts/build.sh` and `scripts/test.sh` are FIXED and define how everything compiles. Do not modify them; make the code conform.
- Compile target: `arm64-apple-macos13.0`. Only use SwiftUI/AppKit APIs available on macOS 13. Do not use the `@Observable` macro (macros unavailable here); use `ObservableObject` + `@Published`. Swift language mode 5 (default), Swift 6.3 compiler.
- File layout (exact):
  - `Sources/Core/*.swift` - pure logic, compiled both into the app and into the smoke test. `import Foundation` only, except `AppInventory.swift` which may `import AppKit`. NO `@main`, no top-level code here.
  - `Sources/App/*.swift` - SwiftUI app, views, view models, snapshot driver. Exactly one `@main` struct.
  - `Tests/smoke.swift` - top-level-code smoke test executable (compiled with Sources/Core only).
  - `scripts/make_icon.swift` - standalone top-level-code program that generates the app icon iconset.
- Text rule: NEVER use the em dash character (U+2014) anywhere: code, strings, comments, docs. Use "-" or rewrite the sentence. Also avoid "·" alternatives that are em dashes; the middle dot "·" itself is fine.
- All user-facing strings in Spanish (proper accents). Code identifiers and comments in English.
- No network access, no telemetry, no git operations. Never write outside the project directory, except: the app at runtime operates on the real user home (that is its purpose), and the smoke test operates ONLY inside a fresh temp directory it creates and removes.
- Do not launch the GUI app yourself; the orchestrator verifies it visually. You MUST get `scripts/test.sh` passing and `scripts/build.sh` succeeding before you are done.

## Safety model (most important)

All destructive operations go through one choke point:

```swift
enum RemovalMode { case permanent, trash }

enum Remover {
    /// Deletes items, refusing anything that does not resolve strictly inside one of allowedRoots.
    static func remove(_ items: [CleanableItem], mode: RemovalMode, allowedRoots: [URL]) -> CleanOutcome
}
```

- Resolve symlinks (`standardizedFileURL.resolvingSymlinksInPath()`) on BOTH the item path and each root before comparison.
- An item qualifies only if its resolved path has a resolved root path + "/" as a strict prefix (path-boundary safe: root "/a/b" must not match "/a/bc"). The root itself never qualifies.
- Items that do not qualify are skipped and reported in `CleanOutcome.failures` with message "Fuera de las rutas permitidas; omitido por seguridad".
- `.permanent` uses `FileManager.removeItem`, `.trash` uses `FileManager.trashItem`.
- `CleanOutcome`: `freedBytes: Int64`, `removedCount: Int`, `failures: [(path: String, message: String)]`.
- Policy: junk categories are deleted permanently (after an explicit confirmation dialog); large files and app uninstalls are moved to the Trash (reversible); emptying the Trash is permanent with a confirmation dialog.

## Sources/Core

### CoreTypes.swift
```swift
struct CleanableItem: Identifiable, Hashable {
    let id: String        // standardized path
    let url: URL
    let name: String      // FileManager displayName
    let detail: String    // parent dir path, with real home prefix abbreviated to "~"
    let size: Int64
    let modified: Date?
    init(url: URL, size: Int64, modified: Date?)
}

struct JunkCategory: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String        // SF Symbol name
    let preselected: Bool
    var items: [CleanableItem]
    var totalSize: Int64    // computed
}

struct CleanOutcome { ... as above ... }

enum ByteFormat { static func string(_ bytes: Int64) -> String }  // ByteCountFormatter, .file style
```

### FileSizer.swift
- `itemSize(at url: URL) -> Int64`: symlink -> 0; directory -> `directorySize`; file -> `totalFileAllocatedSize ?? fileAllocatedSize`.
- `directorySize(at url: URL) -> Int64`: FileManager enumerator summing `totalFileAllocatedSize` of regular files, errorHandler returns true (skip unreadable).
- `modificationDate(at url: URL) -> Date?`.

### Remover.swift
As in the safety model.

### JunkScanner.swift
```swift
struct JunkScanConfig {
    let home: URL                       // init default: FileManager.default.homeDirectoryForCurrentUser
    var excludedCacheNames: Set<String> // default ["com.sebas.MyCleanUp"]
    // roots: caches ~/Library/Caches, logs ~/Library/Logs,
    // savedState ~/Library/Saved Application State,
    // derivedData ~/Library/Developer/Xcode/DerivedData,
    // deviceSupport ~/Library/Developer/Xcode/iOS DeviceSupport,
    // simulatorCaches ~/Library/Developer/CoreSimulator/Caches,
    // xdgCache ~/.cache, npmCache ~/.npm/_cacache
    var allowedRoots: [URL]             // all of the above
}
enum JunkScanner {
    static func scan(config: JunkScanConfig = .init(), progress: ((String) -> Void)? = nil) -> [JunkCategory]
}
```
Categories (skip categories that end up empty; drop items with size 0; skip symlinked children; each category's items sorted by size descending):
1. id "caches", "Cachés de usuario", subtitle "Datos temporales que las apps regeneran cuando los necesitan", icon "archivebox.fill", preselected true. Items = children of caches root (skip hidden, skip `excludedCacheNames`).
2. id "logs", "Registros", "Archivos de registro de apps y diagnósticos", icon "doc.text.fill", preselected true. Children of logs root.
3. id "dev", "Cachés de desarrollo", "DerivedData de Xcode, caché de npm y cachés de herramientas CLI", icon "hammer.fill", preselected true. Items = children of derivedData root + children of xdgCache root + npmCache root as a single item + simulatorCaches root as a single item.
4. id "savedstate", "Estado guardado de apps", "Sesiones de ventanas guardadas; al borrarlas las apps no restauran ventanas", icon "macwindow", preselected false. Children of savedState root.
5. id "devicesupport", "Soporte de dispositivos iOS", "Símbolos de depuración; Xcode los vuelve a descargar si conectas el dispositivo", icon "iphone", preselected false. Children of deviceSupport root.

`progress` receives the path currently being sized (call it per child, throttling is the caller's concern).

### LargeFileScanner.swift
```swift
enum LargeFileScanner {
    struct Progress { let scannedFiles: Int; let currentPath: String }
    static func scan(home: URL = ..., minimumSize: Int64,
                     progress: ((Progress) -> Void)? = nil) -> [CleanableItem]
}
```
- Enumerate home with `.skipsHiddenFiles`, resource keys for regular file, package, symlink, allocated size, modification date, directory.
- Skip descendants of: `home/Library`, any package (`isPackage`), never follow symlinks.
- Collect regular files with allocated size >= minimumSize. Report progress every ~512 files. Return sorted by size descending.

### AppInventory.swift (may import AppKit)
```swift
struct InstalledApp: Identifiable, Hashable {
    let id: String   // path
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    init(url: URL, name: String, bundleID: String?, version: String?)
}
enum AppInventory {
    static func installedApps(home: URL = ...) -> [InstalledApp]
    static func leftovers(for app: InstalledApp, home: URL = ...) -> [CleanableItem]
    static func isRunning(_ app: InstalledApp) -> Bool          // NSRunningApplication
    static func uninstall(app: InstalledApp, appSize: Int64,
                          removingLeftovers: [CleanableItem], home: URL = ...) -> CleanOutcome
}
```
- `installedApps`: scan `/Applications` and `~/Applications` depth 1 for `.app` (skip symlinks). Exclude bundle ids with prefix "com.apple." and our own "com.sebas.MyCleanUp". Sorted by localized name.
- `leftovers`: exact matches only (no fuzzy name substrings). Under `<home>/Library`, check existence of, for bundle id B: `Application Support/B`, `Caches/B`, `Preferences/B.plist`, `Saved Application State/B.savedState`, `WebKit/B`, `HTTPStorages/B`, `HTTPStorages/B.binarycookies`, `Containers/B`, `Application Scripts/B`, `Logs/B`; every file in `LaunchAgents/` whose filename has prefix B; every dir in `Group Containers/` whose name contains B. Additionally, for the display name N: `Application Support/N`, `Caches/N`, `Logs/N`. Deduplicate by path, compute sizes, sort by size descending.
- `uninstall`: leftovers via `Remover.remove(..., mode: .trash, allowedRoots: [home/Library])`, then `trashItem` on the .app itself (add its size and count to the outcome on success; on failure append to failures).

### TrashKit.swift
- `trashURL(home:) -> URL` = `<home>/.Trash`
- `measure(home:) -> (count: Int, size: Int64)`: top-level children count + summed `itemSize`.
- `empty(home:) -> CleanOutcome`: permanently remove each top-level child, collecting failures.

### SystemStats.swift
```swift
struct DiskStats { let total: Int64; let free: Int64; used/usedFraction computed }
struct MemoryStats { let total: Int64; let used: Int64; fraction computed }
enum SystemStats { static func disk() -> DiskStats?; static func memory() -> MemoryStats }
```
- disk: resourceValues of home URL for `.volumeTotalCapacityKey` and `.volumeAvailableCapacityForImportantUsageKey`.
- memory: total = `ProcessInfo.processInfo.physicalMemory`; used = (active + wired + compressor pages) * `vm_page_size` via `host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)` with the usual `withMemoryRebound(to: integer_t.self)` dance; clamp used <= total; on failure used = 0.

### Throttler.swift
Small reference-type helper: `final class Throttler { init(_ interval: TimeInterval); func allow() -> Bool }` so background closures can throttle UI progress updates without mutating captured vars.

## Sources/App

### Main.swift
- `@main struct MyCleanUpApp: App` with a `WindowGroup`, `.defaultSize(width: 1180, height: 740)`.
- `enum AppSection: String, CaseIterable, Identifiable { dashboard, junk, largeFiles, apps, trash }` with Spanish `title` ("Panel de control", "Limpieza del sistema", "Archivos grandes", "Desinstalador", "Papelera") and macOS-13-safe SF Symbol `icon` ("gauge.medium", "sparkles", "shippingbox.fill", "square.grid.2x2.fill", "trash.fill").
- `@MainActor final class AppState: ObservableObject` holding `@Published var section: AppSection = .dashboard` plus the five models (`StatsModel`, `JunkModel`, `LargeFilesModel`, `AppsModel`, `TrashModel`) as lets.
- `ContentView`: `NavigationSplitView`; sidebar `List` with selection bound to the section (Sections: "General" -> Panel; "Limpieza" -> Limpieza del sistema, Archivos grandes, Papelera; "Aplicaciones" -> Desinstalador), `.navigationSplitViewColumnWidth(min: 200, ideal: 230)`, bottom safe-area caption "MyCleanUp 1.0". Detail: switch on section, passing the right model(s). Root `.frame(minWidth: 1040, minHeight: 640)`. Attach `.task { await SnapshotDriver.runIfNeeded(appState) }`.

### Models.swift
`@MainActor` ObservableObject view models. Long work runs in `Task.detached`; results marshaled back with `await MainActor.run`. Progress callbacks throttled with `Throttler` (~0.08s).

- `JunkModel`: `phase` (idle/scanning/done/cleaning, Equatable), `categories`, `selection: Set<String>`, `progressPath`, `lastOutcome`. `scan()` fills categories and preselects items of preselected categories. `clean()` calls `Remover.remove(selected, .permanent, allowedRoots: JunkScanConfig().allowedRoots)`; afterwards removes succeeded items from `categories` (failures stay), drops empty categories, stores outcome, phase back to done. Computed: `totalFound`, `selectedItems`, `selectedSize`.
- `LargeFilesModel`: `phase`, `items`, `selection`, `minimumSize: Int64` (default 100 MB), `progressText` like "12.480 archivos analizados", `lastOutcome`, presets [(50 MB), (100 MB), (500 MB), (1 GB)]. `scan()`, `moveToTrash()` via Remover `.trash` with allowedRoots [home]; remove succeeded from list.
- `AppsModel`: `apps`, `sizes: [String: Int64]` (filled sequentially in background after list loads), `loading`, `query`, `selectedApp: InstalledApp?` (sheet item), `leftovers`, `leftoverSelection`, `loadingLeftovers`, `selectedAppRunning: Bool`, `uninstalling`, `lastOutcome`. `load()`, `openUninstall(app)`, `confirmUninstall()` (on success removes app from list). `filteredApps` honors `query` (case/diacritic insensitive).
- `TrashModel`: `count`, `size`, `working`, `lastOutcome`; `refresh()`, `empty()` then refresh.
- `StatsModel`: `disk: DiskStats?`, `memory: MemoryStats?`; `refresh()`, `refreshMemory()`.

### Theme.swift + Components.swift
- `Theme.gradient`: LinearGradient violet (#6B45E8-ish) to blue (#2E9BF7-ish), topLeading to bottomTrailing. `Theme.accent` violet.
- `.card()` view modifier: padding 16, rounded 16 fill `Color(nsColor: .controlBackgroundColor)`, soft shadow. Must look right in light AND dark mode (use adaptive system colors everywhere; the gradient is fixed).
- `Fmt.date`: DateFormatter locale "es", medium date, no time.
- Reusable components:
  - `CenteredState(icon:title:subtitle:buttonTitle:action:)` - empty/idle states: 96pt gradient circle with white symbol, title `.title2.bold()`, subtitle secondary centered max width ~430, optional `.borderedProminent` `.large` button.
  - `ScanningState(title:detail:)` - spinner, title, one-line secondary detail with middle truncation (max width ~540).
  - `SelectionBar(count:size:actionTitle:busy:action:)` - bottom bar `.background(.bar)`: left "N seleccionados · SIZE" secondary, right prominent large button, disabled when count 0 or busy, small spinner when busy.
  - `OutcomeBanner(outcome:verb:)` - capsule with green checkmark "Se liberaron X" (or verb variant "Se movieron a la Papelera X"), or orange warning "quedaron N elementos con errores" when failures exist, with a "Detalles" popover listing failures (path caption + message).
  - `ItemRow(item:isOn:)` - checkbox toggle (labelsHidden), name, detail caption secondary middle-truncated, spacer, optional modified date caption, size `.monospacedDigit()` secondary; context menu "Mostrar en Finder" (`NSWorkspace.activateFileViewerSelecting`).
  - `IconStore.icon(for path: String) -> NSImage` with NSCache, `NSWorkspace.shared.icon(forFile:)` sized 64.

### DashboardView.swift
ScrollView, VStack spacing 16, padding 24, `.navigationTitle("Panel de control")`:
1. Hero card: rounded 24 `Theme.gradient` fill, padding 28. Left: "Hola, NAME 👋" (first word of `NSFullUserName()`, fallback "Hola 👋") system 28 bold white; subtitle "Recupera espacio y mantén tu Mac en forma." white 90%; white capsule button (plain style, explicit white capsule background, accent-colored label) "Analizar mi Mac" with sparkles icon that triggers `junk.scan()` and navigates to `.junk`. Right: `RingGauge` 148pt: white track 25%, white progress arc (round cap, rotated -90deg) showing disk used fraction, center "NN %" bold white + "usado" caption.
2. Three stat cards in an HStack (equal flexible widths, `.card()`):
   - "Disco": free space `.title2.bold()` + caption "libres de TOTAL". Icon "internaldrive.fill" blue tinted square.
   - "Memoria": used `.title2.bold()` + `ProgressView(value:)` tinted green (orange when fraction > 0.85) + caption "de TOTAL en uso". Icon "memorychip.fill" green.
   - "Papelera": size `.title2.bold()` + caption "N elementos". Icon "trash.fill" orange.
   Missing stats show "N/D", never a dash placeholder.
3. Junk summary card (`.card()`): sparkles icon in gradient square; when junk phase done: "TOTAL de basura encontrada" + button "Revisar y limpiar" -> navigate `.junk`; when scanning: small spinner + "Analizando..."; idle: "Analiza tu Mac para encontrar archivos innecesarios" + button "Analizar".
`.onAppear`: stats.refresh(), trash.refresh(). Timer publisher every 3 s -> stats.refreshMemory(). `.onChange` of junk phase: when it returns to done after cleaning, refresh stats and trash. Use the macOS 13 single-parameter `.onChange(of:perform:)`.

### JunkView.swift
Switch on phase:
- idle: `CenteredState` (sparkles, "Encuentra basura del sistema", subtitle about caches/logs/dev caches, button "Analizar").
- scanning: `ScanningState` ("Analizando tu Mac...", progressPath).
- done/cleaning: VStack: header HStack (title2 bold "Se encontraron TOTAL", spacer, "Volver a analizar" bordered button + optional `OutcomeBanner`); `List` of categories, each a `DisclosureGroup` (per-category `@State` expansion set, collapsed by default): label row = category checkbox (tri-state approximation: on when all items selected; setting toggles all), icon in tinted rounded square, title + subtitle caption, spacer, "N elementos" caption + total size bold; children = `ItemRow`s. Footer `SelectionBar` "Limpiar".
- Confirmation `.alert` before cleaning: title "¿Eliminar N elementos (SIZE)?", message "Los archivos se eliminarán de forma definitiva. Las apps volverán a crear los cachés que necesiten.", destructive "Eliminar" + "Cancelar".
- After clean: `OutcomeBanner`, and `appState.stats.refresh()`.

### LargeFilesView.swift
- Header bar: segmented `Picker` "Tamaño mínimo" over presets + "Analizar" bordered prominent; during scanning `ScanningState` with progressText; idle `CenteredState` (shippingbox, "Encuentra archivos grandes", subtitle noting that macOS puede pedir permiso para acceder a Escritorio, Documentos y Descargas, button "Analizar").
- done: List of `ItemRow`s (file icon via IconStore at 24pt leading), footer `SelectionBar` "Mover a la Papelera" plus caption under bar or in header: "Los archivos se mueven a la Papelera, no se eliminan definitivamente." Confirmation alert before moving. Header shows "N archivos · TOTAL".

### AppsView.swift
- Top bar: rounded-border TextField "Buscar app..." (width ~260) + spacer + "N apps" secondary.
- List rows: app icon 36, name semibold + caption "VERSION · /Applications", spacer, size (small spinner until known), "Desinstalar" bordered button -> `model.openUninstall(app)`.
- `.sheet(item: $model.selectedApp)`: `UninstallSheet` frame ~ (560, 520): header (icon 48, name title3 bold, bundle id caption secondary); if app running: orange label "La app está abierta. Ciérrala antes de desinstalar."; list with Section "Aplicación" (non-toggleable row, always removed) and Section "Archivos relacionados (N)" (`ItemRow`s, all preselected; if none: "Sin archivos residuales conocidos" secondary); footer: total selected size secondary, spacer, "Cancelar" + red prominent "Desinstalar" (disabled while running or uninstalling) with confirmation alert "¿Desinstalar NAME?" message "La app y los archivos seleccionados se moverán a la Papelera.".
- `onAppear`: `model.load()` (only first time). After uninstall show `OutcomeBanner`.

### TrashView.swift
Centered VStack: 96pt gradient circle with white "trash.fill"; size `.largeTitle.bold()`; "N elementos en la Papelera" secondary; caption "Vaciar la Papelera elimina su contenido de forma definitiva."; HStack: bordered "Actualizar" + red prominent "Vaciar Papelera" (disabled when empty or working, spinner while working) with confirmation alert. `OutcomeBanner` after. `.onAppear` refresh.

### Snapshot.swift
Hidden automation mode for E2E evidence, no screen-recording permission needed:
- `SnapshotMode.directory: URL?` parsed once from `CommandLine.arguments` after flag `--snapshot`.
- `@MainActor enum SnapshotDriver { static func runIfNeeded(_ appState: AppState) async }`:
  - Return immediately if no flag. Create the directory. Wait ~0.8 s; take `NSApp.windows.first`, `setContentSize(1180x740)`, center.
  - Capture sequence (PNG via `contentView.bitmapImageRepForCachingDisplay` + `cacheDisplay` + png representation, written as `<name>.png`):
    1. stats+trash refresh, wait ~1.2 s, capture "01-panel".
    2. section .junk, `junk.scan()`, poll every 0.5 s until phase != scanning (cap 240 s), wait 0.6 s, capture "02-limpieza".
    3. section .apps, `apps.load()`, wait 1.5 s then poll until sizes complete (cap 30 s), capture "03-apps".
    4. section .largeFiles, wait 0.8 s, capture "04-archivos-grandes" (idle state, do NOT start a large-file scan: it can trigger TCC prompts).
    5. section .trash, wait 1.0 s, capture "05-papelera".
    6. section .dashboard, wait 0.8 s, capture "06-panel-con-resultados".
  - `NSApp.terminate(nil)` at the end. Never perform any deletion in snapshot mode.

## Tests/smoke.swift

Top-level code, prints "PASS <label>" / "FAIL <label>" per check, final line "ALL TESTS PASSED" or "N TESTS FAILED", exit code 0/1. Everything under `FileManager.default.temporaryDirectory/mycleanup-smoke-<UUID>`, removed at the end. Build a fake home and cover at least:
1. Junk scan finds a fixture cache dir (`Library/Caches/com.foo` with 2 files) in category "caches".
2. Directory size aggregates file sizes (allocated size >= 1.4 MB for 1.5 MB of data).
3. `Remover` refuses a path outside allowedRoots (file survives, failure recorded).
4. `Remover` permanently deletes inside an allowed root (file gone, freedBytes > 0).
5. Large file scan with 2 MB minimum finds exactly the 3 MB fixture file and not smaller ones, and nothing under `Library`.
6. `AppInventory.leftovers` with a fake `InstalledApp(bundleID: "com.bar.app")` finds exactly the fixture `Application Support/com.bar.app` and `Preferences/com.bar.app.plist`.
7. `TrashKit.measure` and `TrashKit.empty` against `<fakehome>/.Trash` with one file (count 1 -> removed -> count 0).
8. `SystemStats.disk()` total > 0 and `SystemStats.memory()` used > 0 on the real machine.

Do not use `trashItem` in tests (it would pollute the real user Trash).

## scripts/make_icon.swift

Standalone program: `make_icon <output.iconset dir>`. Renders the MyCleanUp icon fully in code (AppKit, offscreen, no NSApplication needed):
- Rounded-rect (corner radius 22.37% of side) violet-to-blue gradient matching `Theme.gradient`, subtle large white 12% highlight circle overlapping the top-left, centered white SF Symbol "bubbles.and.sparkles.fill" (fallback "sparkles") at ~55-62% of the side.
- Use the `NSImage(size:flipped:drawingHandler:)` approach so it rasterizes crisply at every size; write the 10 standard iconset PNGs (16, 16@2x, 32, 32@2x, 128, 128@2x, 256, 256@2x, 512, 512@2x) via NSBitmapImageRep.
- `scripts/build.sh` then runs `iconutil` on the result (already wired; just make the program match the contract).

## Definition of done

1. `./scripts/test.sh` prints ALL TESTS PASSED.
2. `./scripts/build.sh` produces `build/MyCleanUp.app` signed ad hoc, with icon.
3. Zero em dash characters in the repo: a recursive search for Unicode U+2014 in Sources, Tests, scripts, and SPEC.md finds nothing.
4. Code compiles without errors; keep SwiftUI bodies decomposed into small computed properties/functions so type checking stays fast.
5. Polished UI: consistent paddings, adaptive colors for light/dark, truncation on long paths, monospaced digits for sizes. This app will be judged visually against CleanMyMac.
