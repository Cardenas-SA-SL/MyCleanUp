import Foundation

enum TrashKit {
    static func trashURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".Trash")
    }

    static func measure(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> (count: Int, size: Int64) {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: trashURL(home: home), includingPropertiesForKeys: nil, options: []
        )) ?? []
        return (children.count, children.reduce(0) { $0 + FileSizer.itemSize(at: $1) })
    }

    static func empty(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> CleanOutcome {
        let root = trashURL(home: home)
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let items = children.map { CleanableItem(url: $0, size: FileSizer.itemSize(at: $0), modified: FileSizer.modificationDate(at: $0)) }
        return Remover.remove(items, mode: .permanent, allowedRoots: [root])
    }
}
