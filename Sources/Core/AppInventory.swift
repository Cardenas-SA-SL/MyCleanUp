import Foundation
import AppKit

struct InstalledApp: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?

    init(url: URL, name: String, bundleID: String?, version: String?) {
        self.url = url.standardizedFileURL
        self.id = url.standardizedFileURL.path
        self.name = name
        self.bundleID = bundleID
        self.version = version
    }
}

enum AppInventory {
    static func installedApps(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [InstalledApp] {
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var apps: [InstalledApp] = []
        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for url in children where url.pathExtension.lowercased() == "app" {
                guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                      let bundle = Bundle(url: url) else { continue }
                let bundleID = bundle.bundleIdentifier
                guard bundleID != "com.sebas.MyCleanUp", bundleID?.hasPrefix("com.apple.") != true else { continue }
                let info = bundle.infoDictionary
                let name = (info?["CFBundleDisplayName"] as? String)
                    ?? (info?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = (info?["CFBundleShortVersionString"] as? String) ?? (info?["CFBundleVersion"] as? String)
                apps.append(InstalledApp(url: url, name: name, bundleID: bundleID, version: version))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func leftovers(for app: InstalledApp, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [CleanableItem] {
        let library = home.appendingPathComponent("Library")
        var candidates: [URL] = []
        if let id = app.bundleID, !id.isEmpty {
            let relative = [
                "Application Support/\(id)", "Caches/\(id)", "Preferences/\(id).plist",
                "Saved Application State/\(id).savedState", "WebKit/\(id)", "HTTPStorages/\(id)",
                "HTTPStorages/\(id).binarycookies", "Containers/\(id)", "Application Scripts/\(id)", "Logs/\(id)"
            ]
            candidates += relative.map { library.appendingPathComponent($0) }
            let launchAgents = library.appendingPathComponent("LaunchAgents")
            if let files = try? FileManager.default.contentsOfDirectory(at: launchAgents, includingPropertiesForKeys: nil) {
                candidates += files.filter { $0.lastPathComponent.hasPrefix(id) }
            }
            let groups = library.appendingPathComponent("Group Containers")
            if let files = try? FileManager.default.contentsOfDirectory(at: groups, includingPropertiesForKeys: [.isDirectoryKey]) {
                candidates += files.filter {
                    $0.lastPathComponent.contains(id) && ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
                }
            }
        }
        candidates += ["Application Support", "Caches", "Logs"].map {
            library.appendingPathComponent($0).appendingPathComponent(app.name)
        }
        var seen = Set<String>()
        return candidates.compactMap { url in
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted, FileManager.default.fileExists(atPath: path),
                  (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return nil }
            return CleanableItem(url: url, size: FileSizer.itemSize(at: url), modified: FileSizer.modificationDate(at: url))
        }.sorted { $0.size > $1.size }
    }

    static func isRunning(_ app: InstalledApp) -> Bool {
        if let id = app.bundleID, !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty { return true }
        return NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL }
    }

    static func uninstall(app: InstalledApp, appSize: Int64,
                          removingLeftovers: [CleanableItem],
                          home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CleanOutcome {
        var outcome = Remover.remove(removingLeftovers, mode: .trash, allowedRoots: [home.appendingPathComponent("Library")])
        do {
            var result: NSURL?
            try FileManager.default.trashItem(at: app.url, resultingItemURL: &result)
            outcome.freedBytes += appSize
            outcome.removedCount += 1
        } catch {
            outcome.failures.append((app.url.path, error.localizedDescription))
        }
        return outcome
    }
}
