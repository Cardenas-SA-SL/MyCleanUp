import Foundation
import AppKit
import SwiftUI

enum SnapshotMode {
    static let directory: URL? = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }()
}

@MainActor
enum SnapshotDriver {
    static func runIfNeeded(_ appState: AppState) async {
        guard let directory = SnapshotMode.directory else { return }
        NSApp.activate(ignoringOtherApps: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        await pause(0.8)
        if let statusWindow = NSApp.windows.first(where: {
            $0.isVisible && $0.windowNumber > 0 &&
            $0.frame.width > 0 && $0.frame.height > 0 &&
            $0.frame.width <= 80 && $0.frame.height <= 80
        }) {
            capture(window: statusWindow, name: "00-icono-menubar", directory: directory)
        }
        guard var mainWindow = visibleMainWindow() else {
            writeCaptureNote("main window unavailable; snapshot run stopped")
            return
        }
        mainWindow.makeKeyAndOrderFront(nil)
        mainWindow.setContentSize(NSSize(width: 1180, height: 740))
        mainWindow.center()

        appState.stats.refresh()
        appState.trash.refresh()
        await pause(1.2)
        if let refreshed = captureMainWindow(preferred: mainWindow, name: "01-panel", directory: directory) {
            mainWindow = refreshed
        }

        appState.section = .junk
        appState.junk.scan()
        await waitUntil(timeout: 240) { appState.junk.phase != .scanning }
        await pause(0.6)
        if let refreshed = captureMainWindow(preferred: mainWindow, name: "02-limpieza", directory: directory) {
            mainWindow = refreshed
        }

        appState.section = .apps
        appState.apps.load()
        await pause(1.5)
        await waitUntil(timeout: 30) { !appState.apps.loading && appState.apps.sizes.count >= appState.apps.apps.count }
        if let refreshed = captureMainWindow(preferred: mainWindow, name: "03-apps", directory: directory) {
            mainWindow = refreshed
        }

        appState.section = .largeFiles
        await pause(0.8)
        if let refreshed = captureMainWindow(preferred: mainWindow, name: "04-archivos-grandes", directory: directory) {
            mainWindow = refreshed
        }

        appState.section = .trash
        await pause(1.0)
        if let refreshed = captureMainWindow(preferred: mainWindow, name: "05-papelera", directory: directory) {
            mainWindow = refreshed
        }

        appState.section = .dashboard
        await pause(0.8)
        if let refreshed = captureMainWindow(preferred: mainWindow, name: "06-panel-con-resultados", directory: directory) {
            mainWindow = refreshed
        }

        let menuBarView = NSHostingView(rootView: MenuBarView(appState: appState))
        let fittingSize = menuBarView.fittingSize
        let menuWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: max(1, fittingSize.height)),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        menuWindow.isOpaque = false
        menuWindow.backgroundColor = .clear
        menuWindow.hasShadow = true
        menuWindow.level = .floating
        menuWindow.contentView = menuBarView
        menuWindow.center()
        menuWindow.makeKeyAndOrderFront(nil)
        await pause(2.0)
        capture(window: menuWindow, name: "07-menubar", directory: directory)

        appState.menuBar.optimize()
        await waitUntil(timeout: 45) {
            if case .running = appState.menuBar.optimizerState { return false }
            return true
        }
        await pause(0.6)
        capture(window: menuWindow, name: "08-menubar-optimizada", directory: directory)
        menuWindow.close()
        NSApp.terminate(nil)
    }

    private static func waitUntil(timeout: TimeInterval, condition: @escaping @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { await pause(0.5) }
    }

    private static func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func visibleMainWindow(preferred: NSWindow? = nil) -> NSWindow? {
        if let preferred,
           preferred.isVisible,
           preferred.windowNumber > 0,
           preferred.styleMask.contains(.titled) {
            return preferred
        }
        return NSApp.windows.first {
            $0.isVisible && $0.windowNumber > 0 && $0.styleMask.contains(.titled)
        }
    }

    @discardableResult
    private static func captureMainWindow(preferred: NSWindow?, name: String, directory: URL) -> NSWindow? {
        guard let window = visibleMainWindow(preferred: preferred) else {
            writeCaptureNote("capture skipped for \(name): main window unavailable")
            return nil
        }
        capture(window: window, name: name, directory: directory)
        return window
    }

    private static func writeCaptureNote(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    private static func capture(window: NSWindow, name: String, directory: URL) {
        let number = window.windowNumber
        guard window.isVisible, number > 0, number <= Int(UInt32.max) else {
            writeCaptureNote("capture skipped for \(name): window is hidden or has an invalid number")
            return
        }
        // SwiftUI draws through Metal surfaces that neither cacheDisplay nor CALayer.render can read,
        // so ask WindowServer for the composited pixels of our own window (no permission needed).
        let windowID = CGWindowID(number)
        guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID,
                                                    [.boundsIgnoreFraming, .bestResolution]) else {
            FileHandle.standardError.write(Data("capture failed for \(name)\n".utf8))
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
}
