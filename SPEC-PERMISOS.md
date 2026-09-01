# MyCleanUp - Addendum v1.4: manejo del permiso Gestion de apps en el desinstalador

Real bug report: uninstalling Microsoft Word left "Quedaron 2 elementos con errores". Cause: on macOS 13+ deleting ANOTHER app's bundle (and its ~/Library/Containers data) requires the TCC permission "App Management"; without it FileManager.trashItem fails with a permission error. The app must detect this and guide the user instead of showing a generic error. All existing constraints apply (fixed scripts untouched, Spanish UI, no em dash U+2014, macOS 13 APIs, ObservableObject, no GUI launch by you, no git).

## 1. Detect permission failures (Sources/Core)

In Remover (or a small helper next to it): classify an error as a permissions failure when it is a CocoaError with code .fileWriteNoPermission (513) or its underlying NSPOSIXErrorDomain error is EPERM (1) or EACCES (13). Extend CleanOutcome failures so each entry also carries `esPermiso: Bool` (change the tuple to a small struct `CleanFailure { path, message, esPermiso }`; update all uses in Core, Tests and App: JunkModel, LargeFilesModel, AppsModel, OutcomeBanner failure list, smoke assertions).

## 2. Uninstall flow UX (Sources/App)

- AppsModel.confirmUninstall already leaves the sheet open when the .app fails. Add `@Published var permisoRequerido: Bool` set true when any failure of the last uninstall outcome has esPermiso.
- In UninstallSheet: when `permisoRequerido`, show INSIDE the sheet (above the footer) a highlighted panel:
  titulo "macOS bloqueo la eliminacion"
  texto: "Para desinstalar otras apps, macOS exige autorizar a MyCleanUp en Gestion de apps. Activa MyCleanUp y reintenta."
  Buttons: "Abrir Ajustes" -> NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!) (if that anchor fails to open, fall back to "x-apple.systempreferences:com.apple.preference.security"); "Reintentar" -> runs confirmUninstall() again.
- Non-permission failures keep current behavior (banner + Detalles popover), but the Detalles popover should mark permission entries with a lock icon and the same one-line hint.
- The banner OutcomeBanner shown behind the sheet stays as is.

## 3. Smoke test (Tests/smoke.swift)

Pure test for the classifier: build an NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 1)]) and assert it classifies as permiso; a generic error (e.g. fileNoSuchFile 4) classifies as no-permiso. Keep ALL existing tests passing; ./scripts/test.sh must print ALL TESTS PASSED and ./scripts/build.sh must succeed.
