import Foundation

struct JunkScanConfig {
    let home: URL
    var excludedCacheNames: Set<String>

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         excludedCacheNames: Set<String> = ["com.sebas.MyCleanUp"]) {
        self.home = home.standardizedFileURL
        self.excludedCacheNames = excludedCacheNames
    }

    var caches: URL { home.appendingPathComponent("Library/Caches") }
    var logs: URL { home.appendingPathComponent("Library/Logs") }
    var savedState: URL { home.appendingPathComponent("Library/Saved Application State") }
    var derivedData: URL { home.appendingPathComponent("Library/Developer/Xcode/DerivedData") }
    var deviceSupport: URL { home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport") }
    var simulatorCaches: URL { home.appendingPathComponent("Library/Developer/CoreSimulator/Caches") }
    var xdgCache: URL { home.appendingPathComponent(".cache") }
    var npmCache: URL { home.appendingPathComponent(".npm/_cacache") }
    var allowedRoots: [URL] {
        [caches, logs, savedState, derivedData, deviceSupport, simulatorCaches, xdgCache, npmCache]
    }
}

enum JunkScanner {
    static func scan(config: JunkScanConfig = .init(), progress: ((String) -> Void)? = nil) -> [JunkCategory] {
        func children(_ root: URL, excluding: Set<String> = []) -> [CleanableItem] {
            let keys: Set<URLResourceKey> = [.isHiddenKey, .isSymbolicLinkKey, .contentModificationDateKey]
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
            ) else { return [] }
            return urls.compactMap { url in
                guard !excluding.contains(url.lastPathComponent),
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isHidden != true, values.isSymbolicLink != true else { return nil }
                progress?(url.path)
                let size = FileSizer.itemSize(at: url)
                guard size > 0 else { return nil }
                return CleanableItem(url: url, size: size, modified: values.contentModificationDate)
            }.sorted { $0.size > $1.size }
        }

        func single(_ url: URL) -> [CleanableItem] {
            guard FileManager.default.fileExists(atPath: url.path),
                  (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return [] }
            progress?(url.path)
            let size = FileSizer.itemSize(at: url)
            guard size > 0 else { return [] }
            return [CleanableItem(url: url, size: size, modified: FileSizer.modificationDate(at: url))]
        }

        var categories: [JunkCategory] = []
        let definitions: [(String, String, String, String, Bool, [CleanableItem])] = [
            ("caches", "Cachés de usuario", "Datos temporales que las apps regeneran cuando los necesitan", "archivebox.fill", true, children(config.caches, excluding: config.excludedCacheNames)),
            ("logs", "Registros", "Archivos de registro de apps y diagnósticos", "doc.text.fill", true, children(config.logs)),
            ("dev", "Cachés de desarrollo", "DerivedData de Xcode, caché de npm y cachés de herramientas CLI", "hammer.fill", true, (children(config.derivedData) + children(config.xdgCache) + single(config.npmCache) + single(config.simulatorCaches)).sorted { $0.size > $1.size }),
            ("savedstate", "Estado guardado de apps", "Sesiones de ventanas guardadas; al borrarlas las apps no restauran ventanas", "macwindow", false, children(config.savedState)),
            ("devicesupport", "Soporte de dispositivos iOS", "Símbolos de depuración; Xcode los vuelve a descargar si conectas el dispositivo", "iphone", false, children(config.deviceSupport))
        ]
        for definition in definitions where !definition.5.isEmpty {
            categories.append(JunkCategory(id: definition.0, title: definition.1, subtitle: definition.2, icon: definition.3, preselected: definition.4, items: definition.5))
        }
        return categories
    }
}
