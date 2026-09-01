import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() { print("PASS \(label)") }
    else { print("FAIL \(label)"); failures += 1 }
}

func write(_ url: URL, megabytes: Int) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x5A, count: megabytes * 1_048_576).write(to: url)
}

func write(_ url: URL, bytes: Int) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x5A, count: bytes).write(to: url)
}

@main
struct SmokeTest {
static func main() {
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("mycleanup-smoke-\(UUID().uuidString)")
let home = root.appendingPathComponent("home")
do {
    try fm.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let cache = home.appendingPathComponent("Library/Caches/com.foo")
    try write(cache.appendingPathComponent("a.bin"), megabytes: 1)
    try write(cache.appendingPathComponent("b.bin"), megabytes: 1)
    let categories = JunkScanner.scan(config: JunkScanConfig(home: home))
    check(categories.first(where: { $0.id == "caches" })?.items.contains(where: { $0.url.lastPathComponent == "com.foo" }) == true, "escaneo de cachés")
    check(FileSizer.directorySize(at: cache) >= 1_400_000, "tamaño de directorio")

    let framework = home.appendingPathComponent("fixtures/fw")
    let frameworkFile = framework.appendingPathComponent("Versions/big.bin")
    try write(frameworkFile, bytes: 320_000)
    try fm.createSymbolicLink(atPath: framework.appendingPathComponent("Current").path, withDestinationPath: "Versions")
    check(FileSizer.directorySize(at: framework) >= 300_000, "tamaño tras enlace simbólico hermano")

    let scanParent = home.appendingPathComponent("ScanTarget")
    let largeAfterLink = scanParent.appendingPathComponent("Z-large.bin")
    try write(largeAfterLink, bytes: 400_000)
    try fm.createSymbolicLink(atPath: scanParent.appendingPathComponent("A-current").path, withDestinationPath: ".")
    let symlinkScan = LargeFileScanner.scan(home: home, minimumSize: 300_000)
    check(symlinkScan.contains(where: { $0.url.lastPathComponent == "Z-large.bin" }), "archivo grande tras enlace simbólico hermano")

    let allowed = home.appendingPathComponent("allowed")
    try fm.createDirectory(at: allowed, withIntermediateDirectories: true)
    let outside = home.appendingPathComponent("outside.bin")
    try write(outside, megabytes: 1)
    let outsideItem = CleanableItem(url: outside, size: FileSizer.itemSize(at: outside), modified: nil)
    let refused = Remover.remove([outsideItem], mode: .permanent, allowedRoots: [allowed])
    check(fm.fileExists(atPath: outside.path) && refused.failures.count == 1, "rechazo fuera de ruta")

    let inside = allowed.appendingPathComponent("inside.bin")
    try write(inside, megabytes: 1)
    let insideItem = CleanableItem(url: inside, size: FileSizer.itemSize(at: inside), modified: nil)
    let removed = Remover.remove([insideItem], mode: .permanent, allowedRoots: [allowed])
    check(!fm.fileExists(atPath: inside.path) && removed.freedBytes > 0, "eliminación permitida")

    try write(home.appendingPathComponent("Documents/grande.bin"), megabytes: 3)
    try write(home.appendingPathComponent("Documents/pequeño.bin"), megabytes: 1)
    try write(home.appendingPathComponent("Library/grande-oculto.bin"), megabytes: 3)
    let large = LargeFileScanner.scan(home: home, minimumSize: 2 * 1_048_576)
    check(large.count == 1 && large[0].name == "grande.bin", "archivos grandes")

    let support = home.appendingPathComponent("Library/Application Support/com.bar.app")
    let preference = home.appendingPathComponent("Library/Preferences/com.bar.app.plist")
    try write(support.appendingPathComponent("data.bin"), megabytes: 1)
    try write(preference, megabytes: 1)
    let fakeApp = InstalledApp(url: home.appendingPathComponent("Applications/Bar.app"), name: "Bar", bundleID: "com.bar.app", version: "1")
    let leftovers = AppInventory.leftovers(for: fakeApp, home: home)
    check(Set(leftovers.map(\.url.path)) == Set([support.path, preference.path]), "residuos exactos")

    let trashFile = home.appendingPathComponent(".Trash/trash.bin")
    try write(trashFile, megabytes: 1)
    check(TrashKit.measure(home: home).count == 1, "medición de Papelera")
    _ = TrashKit.empty(home: home)
    check(TrashKit.measure(home: home).count == 0, "vaciado de Papelera")

    let planningSnapshot = MemoryPressureSnapshot(
        free: 600, active: 0, inactive: 500, speculative: 200,
        wired: 0, compressed: 0, total: 1_000
    )
    let planned = MemoryOptimizer.plannedAllocation(for: planningSnapshot, maxBytes: 400)
    check(planned <= planningSnapshot.total / 2 && planned <= 400, "límites del optimizador de memoria")
    let zeroSnapshot = MemoryPressureSnapshot(
        free: 0, active: 0, inactive: 0, speculative: 0,
        wired: 0, compressed: 0, total: 0
    )
    check(MemoryOptimizer.plannedAllocation(for: zeroSnapshot, maxBytes: -1) == 0,
          "plan de memoria nunca negativo")

    let healthyMemory = MemoryPressureSnapshot(
        free: 300, active: 400, inactive: 100, speculative: 0,
        wired: 100, compressed: 100, total: 1_000
    )
    let lowAvailableMemory = MemoryPressureSnapshot(
        free: 100, active: 600, inactive: 100, speculative: 0,
        wired: 100, compressed: 100, total: 1_000
    )
    let compressedMemory = MemoryPressureSnapshot(
        free: 300, active: 200, inactive: 100, speculative: 0,
        wired: 100, compressed: 300, total: 1_000
    )
    check(!MemoryOptimizer.hasMemoryPressure(healthyMemory), "memoria saludable sin presión")
    check(MemoryOptimizer.hasMemoryPressure(lowAvailableMemory), "presión por memoria disponible baja")
    check(MemoryOptimizer.hasMemoryPressure(compressedMemory), "presión por memoria comprimida alta")

    let optimizeResult = MemoryOptimizer.optimize(maxBytes: 128 * 1_048_576, timeLimit: 3)
    check(optimizeResult.freedBytes >= 0 && optimizeResult.duration < 10,
          "optimización pequeña de memoria")

    let battery = PowerStats.battery()
    let batteryIsSane = !battery.hasBattery || (
        (0...100).contains(battery.percent) &&
        (battery.minutesRemaining == nil || battery.minutesRemaining! > 0) &&
        (!battery.isCharging || battery.onACPower)
    )
    check(batteryIsSane, "estadísticas de batería")

    let cpuSampler = CPULoadSampler()
    let wrappedTick = CPULoadSampler.unsignedTick(Int32(bitPattern: 0xF000_0000))
    check(wrappedTick == 4_026_531_840, "conversión de contador CPU sin desbordamiento")
    _ = cpuSampler.sample()
    Thread.sleep(forTimeInterval: 0.2)
    let cpuLoad = cpuSampler.sample()
    check((0...1).contains(cpuLoad), "muestreo de CPU")

    let netSampler = NetRateSampler()
    _ = netSampler.sample()
    Thread.sleep(forTimeInterval: 0.05)
    let rates = netSampler.sample()
    check(rates.up >= 0 && rates.down >= 0, "muestreo de red")

    check((SystemStats.disk()?.total ?? 0) > 0, "estadísticas de disco")
    check(SystemStats.memory().used > 0, "estadísticas de memoria")
} catch {
    print("FAIL preparación: \(error)")
    failures += 1
}

if failures == 0 {
    print("ALL TESTS PASSED")
    exit(0)
} else {
    print("\(failures) TESTS FAILED")
    exit(1)
}
}
}
