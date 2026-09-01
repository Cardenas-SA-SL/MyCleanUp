import Foundation

enum RemovalMode { case permanent, trash }

enum Remover {
    static func remove(_ items: [CleanableItem], mode: RemovalMode, allowedRoots: [URL]) -> CleanOutcome {
        var outcome = CleanOutcome()
        let roots = allowedRoots.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        for item in items {
            let resolved = item.url.standardizedFileURL.resolvingSymlinksInPath()
            let allowed = roots.contains { resolved.path.hasPrefix($0 + "/") }
            guard allowed else {
                outcome.failures.append((item.url.path, "Fuera de las rutas permitidas; omitido por seguridad"))
                continue
            }
            do {
                switch mode {
                case .permanent:
                    try FileManager.default.removeItem(at: resolved)
                case .trash:
                    var result: NSURL?
                    try FileManager.default.trashItem(at: resolved, resultingItemURL: &result)
                }
                outcome.freedBytes += item.size
                outcome.removedCount += 1
            } catch {
                outcome.failures.append((item.url.path, error.localizedDescription))
            }
        }
        return outcome
    }
}
