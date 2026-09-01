import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, junk, largeFiles, apps, trash
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Panel de control"
        case .junk: return "Limpieza del sistema"
        case .largeFiles: return "Archivos grandes"
        case .apps: return "Desinstalador"
        case .trash: return "Papelera"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .junk: return "sparkles"
        case .largeFiles: return "shippingbox.fill"
        case .apps: return "square.grid.2x2.fill"
        case .trash: return "trash.fill"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var section: AppSection = .dashboard
    let stats = StatsModel()
    let junk = JunkModel()
    let largeFiles = LargeFilesModel()
    let apps = AppsModel()
    let trash = TrashModel()
    let menuBar = MenuBarModel()
}

@main
struct MyCleanUpApp: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup(id: "main") { ContentView(appState: appState) }
            .defaultSize(width: 1180, height: 740)
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: "bubbles.and.sparkles").renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 1040, minHeight: 640)
        .task { await SnapshotDriver.runIfNeeded(appState) }
    }

    private var sidebar: some View {
        List(selection: $appState.section) {
            Section("General") { navItem(.dashboard) }
            Section("Limpieza") {
                navItem(.junk)
                navItem(.largeFiles)
                navItem(.trash)
            }
            Section("Aplicaciones") { navItem(.apps) }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        .safeAreaInset(edge: .bottom) {
            Text("MyCleanUp 1.0").font(.caption2).foregroundStyle(.tertiary).padding(.vertical, 10)
        }
    }

    private func navItem(_ section: AppSection) -> some View {
        Label(section.title, systemImage: section.icon).tag(section)
    }

    @ViewBuilder private var detail: some View {
        switch appState.section {
        case .dashboard: DashboardView(appState: appState)
        case .junk: JunkView(appState: appState, model: appState.junk)
        case .largeFiles: LargeFilesView(model: appState.largeFiles)
        case .apps: AppsView(model: appState.apps)
        case .trash: TrashView(model: appState.trash)
        }
    }
}
