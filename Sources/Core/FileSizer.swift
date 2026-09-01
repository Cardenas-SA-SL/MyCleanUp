import Foundation

enum FileSizer {
    static func itemSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [
            .isSymbolicLinkKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey
        ]), values.isSymbolicLink != true else { return 0 }
        if values.isDirectory == true { return directorySize(at: url) }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    static func directorySize(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                continue
            }
            if values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    static func modificationDate(at url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
