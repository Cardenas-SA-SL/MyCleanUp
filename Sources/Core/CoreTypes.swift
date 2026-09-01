import Foundation

struct CleanableItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let detail: String
    let size: Int64
    let modified: Date?

    init(url: URL, size: Int64, modified: Date?) {
        let standardized = url.standardizedFileURL
        self.id = standardized.path
        self.url = standardized
        self.name = FileManager.default.displayName(atPath: standardized.path)
        let parent = standardized.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if parent == home {
            self.detail = "~"
        } else if parent.hasPrefix(home + "/") {
            self.detail = "~" + String(parent.dropFirst(home.count))
        } else {
            self.detail = parent
        }
        self.size = size
        self.modified = modified
    }
}

struct JunkCategory: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let preselected: Bool
    var items: [CleanableItem]
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

struct CleanFailure {
    let path: String
    let message: String
    let esPermiso: Bool
}

struct CleanOutcome {
    var freedBytes: Int64 = 0
    var removedCount: Int = 0
    var failures: [CleanFailure] = []
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
