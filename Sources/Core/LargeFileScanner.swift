import Foundation

enum LargeFileScanner {
    struct Progress { let scannedFiles: Int; let currentPath: String }

    static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     minimumSize: Int64,
                     progress: ((Progress) -> Void)? = nil) -> [CleanableItem] {
        let home = home.standardizedFileURL
        let library = home.appendingPathComponent("Library").standardizedFileURL.path
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isPackageKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey, .contentModificationDateKey, .isDirectoryKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }
        var items: [CleanableItem] = []
        var scanned = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if url.standardizedFileURL.path == library {
                enumerator.skipDescendants()
                continue
            }
            if values.isSymbolicLink == true {
                continue
            }
            if values.isPackage == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            scanned += 1
            if scanned % 512 == 0 { progress?(Progress(scannedFiles: scanned, currentPath: url.path)) }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            if size >= minimumSize {
                items.append(CleanableItem(url: url, size: size, modified: values.contentModificationDate))
            }
        }
        progress?(Progress(scannedFiles: scanned, currentPath: home.path))
        return items.sorted { $0.size > $1.size }
    }
}
