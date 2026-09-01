import Foundation

enum RemovalMode { case permanent, trash }

enum RemovalErrorClassifier {
    static func isPermission(_ error: Error) -> Bool {
        isPermission(error as NSError, depth: 0)
    }

    private static func isPermission(_ error: NSError, depth: Int) -> Bool {
        guard depth < 8 else { return false }
        if error.domain == NSCocoaErrorDomain,
           error.code == CocoaError.Code.fileWriteNoPermission.rawValue { return true }
        if error.domain == NSPOSIXErrorDomain,
           error.code == 1 || error.code == 13 { return true }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
        return isPermission(underlying, depth: depth + 1)
    }
}

enum Remover {
    static func remove(_ items: [CleanableItem], mode: RemovalMode, allowedRoots: [URL]) -> CleanOutcome {
        var outcome = CleanOutcome()
        let roots = allowedRoots.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        for item in items {
            let resolved = item.url.standardizedFileURL.resolvingSymlinksInPath()
            let allowed = roots.contains { resolved.path.hasPrefix($0 + "/") }
            guard allowed else {
                outcome.failures.append(CleanFailure(
                    path: item.url.path,
                    message: "Fuera de las rutas permitidas; omitido por seguridad",
                    esPermiso: false
                ))
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
                outcome.failures.append(CleanFailure(
                    path: item.url.path,
                    message: error.localizedDescription,
                    esPermiso: RemovalErrorClassifier.isPermission(error)
                ))
            }
        }
        return outcome
    }
}
