import Foundation
import SwiftUI

enum WorkPhase: Equatable { case idle, scanning, done, cleaning }

@MainActor
final class JunkModel: ObservableObject {
    @Published var phase: WorkPhase = .idle
    @Published var categories: [JunkCategory] = []
    @Published var selection = Set<String>()
    @Published var progressPath = ""
    @Published var lastOutcome: CleanOutcome?

    var totalFound: Int64 { categories.reduce(0) { $0 + $1.totalSize } }
    var selectedItems: [CleanableItem] { categories.flatMap(\.items).filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func scan() {
        guard phase != .scanning, phase != .cleaning else { return }
        phase = .scanning
        progressPath = "Preparando análisis..."
        lastOutcome = nil
        let throttler = Throttler(0.08)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                JunkScanner.scan { path in
                    if throttler.allow() { Task { @MainActor in self.progressPath = path } }
                }
            }.value
            categories = result
            selection = Set(result.filter(\.preselected).flatMap(\.items).map(\.id))
            phase = .done
        }
    }

    func clean() {
        let items = selectedItems
        guard !items.isEmpty, phase == .done else { return }
        phase = .cleaning
        let roots = JunkScanConfig().allowedRoots
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Remover.remove(items, mode: .permanent, allowedRoots: roots)
            }.value
            let failed = Set(outcome.failures.map(\.path))
            let succeeded = Set(items.filter { !failed.contains($0.url.path) }.map(\.id))
            categories = categories.compactMap { category in
                var copy = category
                copy.items.removeAll { succeeded.contains($0.id) }
                return copy.items.isEmpty ? nil : copy
            }
            selection.subtract(succeeded)
            lastOutcome = outcome
            phase = .done
        }
    }
}

@MainActor
final class LargeFilesModel: ObservableObject {
    @Published var phase: WorkPhase = .idle
    @Published var items: [CleanableItem] = []
    @Published var selection = Set<String>()
    @Published var minimumSize: Int64 = 100 * 1_048_576
    @Published var progressText = ""
    @Published var lastOutcome: CleanOutcome?
    let presets: [Int64] = [50, 100, 500, 1024].map { $0 * 1_048_576 }

    var selectedItems: [CleanableItem] { items.filter { selection.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    func scan() {
        guard phase != .scanning else { return }
        phase = .scanning
        selection.removeAll()
        lastOutcome = nil
        progressText = "Preparando análisis..."
        let threshold = minimumSize
        let throttler = Throttler(0.08)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                LargeFileScanner.scan(minimumSize: threshold) { progress in
                    if throttler.allow() {
                        Task { @MainActor in
                            self.progressText = pluralized(progress.scannedFiles, "archivo analizado", "archivos analizados")
                        }
                    }
                }
            }.value
            items = result
            phase = .done
        }
    }

    func moveToTrash() {
        let selected = selectedItems
        guard !selected.isEmpty else { return }
        phase = .cleaning
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Remover.remove(selected, mode: .trash, allowedRoots: [home])
            }.value
            let failed = Set(outcome.failures.map(\.path))
            let succeeded = Set(selected.filter { !failed.contains($0.url.path) }.map(\.id))
            items.removeAll { succeeded.contains($0.id) }
            selection.subtract(succeeded)
            lastOutcome = outcome
            phase = .done
        }
    }
}

@MainActor
final class AppsModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var sizes: [String: Int64] = [:]
    @Published var loading = false
    @Published var query = ""
    @Published var selectedApp: InstalledApp?
    @Published var leftovers: [CleanableItem] = []
    @Published var leftoverSelection = Set<String>()
    @Published var loadingLeftovers = false
    @Published var selectedAppRunning = false
    @Published var uninstalling = false
    @Published var lastOutcome: CleanOutcome?
    private var hasLoaded = false

    var filteredApps: [InstalledApp] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    func load() {
        guard !hasLoaded, !loading else { return }
        hasLoaded = true
        loading = true
        Task {
            let found = await Task.detached(priority: .userInitiated) { AppInventory.installedApps() }.value
            apps = found
            loading = false
            for app in found {
                let size = await Task.detached(priority: .utility) { FileSizer.itemSize(at: app.url) }.value
                sizes[app.id] = size
            }
        }
    }

    func openUninstall(_ app: InstalledApp) {
        selectedApp = app
        leftovers = []
        leftoverSelection = []
        loadingLeftovers = true
        selectedAppRunning = AppInventory.isRunning(app)
        Task {
            let found = await Task.detached(priority: .userInitiated) { AppInventory.leftovers(for: app) }.value
            guard selectedApp?.id == app.id else { return }
            leftovers = found
            leftoverSelection = Set(found.map(\.id))
            selectedAppRunning = AppInventory.isRunning(app)
            loadingLeftovers = false
        }
    }

    func confirmUninstall() {
        guard let app = selectedApp, !selectedAppRunning else { return }
        let selected = leftovers.filter { leftoverSelection.contains($0.id) }
        let size = sizes[app.id] ?? FileSizer.itemSize(at: app.url)
        uninstalling = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                AppInventory.uninstall(app: app, appSize: size, removingLeftovers: selected)
            }.value
            lastOutcome = outcome
            uninstalling = false
            if !outcome.failures.contains(where: { $0.path == app.url.path }) {
                apps.removeAll { $0.id == app.id }
                sizes.removeValue(forKey: app.id)
                selectedApp = nil
            }
        }
    }
}

@MainActor
final class TrashModel: ObservableObject {
    @Published var count = 0
    @Published var size: Int64 = 0
    @Published var working = false
    @Published var lastOutcome: CleanOutcome?

    func refresh() {
        guard !working else { return }
        working = true
        Task {
            let result = await Task.detached(priority: .utility) { TrashKit.measure() }.value
            count = result.count
            size = result.size
            working = false
        }
    }

    func empty() {
        guard count > 0, !working else { return }
        working = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { TrashKit.empty() }.value
            lastOutcome = outcome
            let result = await Task.detached(priority: .utility) { TrashKit.measure() }.value
            count = result.count
            size = result.size
            working = false
        }
    }
}

@MainActor
final class StatsModel: ObservableObject {
    @Published var disk: DiskStats?
    @Published var memory: MemoryStats?

    func refresh() {
        let shouldRefreshMemory = !MenuBarModel.isOptimizing
        Task {
            let values = await Task.detached(priority: .utility) { (SystemStats.disk(), SystemStats.memory()) }.value
            disk = values.0
            if shouldRefreshMemory, !MenuBarModel.isOptimizing { memory = values.1 }
        }
    }

    func refreshMemory() {
        guard !MenuBarModel.isOptimizing else { return }
        Task {
            let value = await Task.detached(priority: .utility) { SystemStats.memory() }.value
            if !MenuBarModel.isOptimizing { memory = value }
        }
    }
}

enum OptimizerState {
    case idle
    case running
    case result(OptimizeResult)
}

@MainActor
final class MenuBarModel: ObservableObject {
    static var isOptimizing = false

    @Published var disk: DiskStats?
    @Published var memory: MemoryPressureSnapshot
    @Published var memoryAvailable: Int64
    @Published var battery = PowerStats.battery()
    @Published var cpuLoad: Double = 0
    @Published var netUp: Int64 = 0
    @Published var netDown: Int64 = 0
    @Published var optimizerState: OptimizerState = .idle

    private let cpuSampler = CPULoadSampler()
    private let netSampler = NetRateSampler()
    private var refreshTimer: Timer?
    private var optimizerRunID: UUID?

    var coreCount: Int { cpuSampler.coreCount }

    init() {
        let initialMemory = MemoryOptimizer.snapshot()
        memory = initialMemory
        memoryAvailable = initialMemory.available
    }

    func startRefreshing() {
        guard refreshTimer == nil else { return }
        refreshAll()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refreshAll() {
        disk = SystemStats.disk()
        if !Self.isOptimizing {
            memory = MemoryOptimizer.snapshot()
            memoryAvailable = memory.available
        }
        battery = PowerStats.battery()
        cpuLoad = cpuSampler.sample()
        let rates = netSampler.sample()
        netUp = rates.up
        netDown = rates.down
    }

    func optimize() {
        guard case .idle = optimizerState else { return }
        let runID = UUID()
        optimizerRunID = runID
        Self.isOptimizing = true
        optimizerState = .running
        Task {
            let result = await Task.detached(priority: .utility) {
                MemoryOptimizer.optimize()
            }.value
            guard optimizerRunID == runID else { return }
            Self.isOptimizing = false
            refreshAll()
            optimizerState = .result(result)
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard optimizerRunID == runID else { return }
            optimizerState = .idle
            optimizerRunID = nil
        }
    }
}
