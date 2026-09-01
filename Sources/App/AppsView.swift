import SwiftUI
import AppKit

struct AppsView: View {
    @ObservedObject var model: AppsModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if model.loading { ScanningState(title: "Buscando aplicaciones...", detail: "Revisando las aplicaciones instaladas") }
            else { appList }
            if let outcome = model.lastOutcome { OutcomeBanner(outcome: outcome, verb: "Se movieron a la Papelera").padding(12) }
        }
        .navigationTitle("Desinstalador")
        .onAppear { model.load() }
        .sheet(item: $model.selectedApp) { app in UninstallSheet(model: model, app: app) }
    }

    private var topBar: some View {
        HStack {
            TextField("Buscar app...", text: $model.query).textFieldStyle(.roundedBorder).frame(width: 260)
            Spacer()
            Text(pluralized(model.filteredApps.count, "app", "apps")).foregroundStyle(.secondary)
        }.padding(20)
    }

    private var appList: some View {
        List(model.filteredApps) { app in
            HStack(spacing: 12) {
                Image(nsImage: IconStore.icon(for: app.url.path)).resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).fontWeight(.semibold).lineLimit(1)
                    Text("\(app.version ?? "Versión desconocida") · \(app.url.deletingLastPathComponent().path)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if let size = model.sizes[app.id] {
                    Text(ByteFormat.string(size)).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 80, alignment: .trailing)
                } else { ProgressView().controlSize(.small).frame(width: 80) }
                Button("Desinstalar") { model.openUninstall(app) }.buttonStyle(.bordered)
            }.padding(.vertical, 5)
        }.listStyle(.inset)
    }
}

private struct UninstallSheet: View {
    @ObservedObject var model: AppsModel
    let app: InstalledApp
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            if model.permisoRequerido {
                permissionPanel
                Divider()
            }
            footer
        }.frame(width: 560, height: 520)
        .alert("¿Desinstalar \(app.name)?", isPresented: $confirming) {
            Button("Desinstalar", role: .destructive) { model.confirmUninstall() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("La app y los archivos seleccionados se moverán a la Papelera.") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: IconStore.icon(for: app.url.path)).resizable().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.title3.bold())
                Text(app.bundleID ?? "Sin identificador de paquete").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(20)
    }

    @ViewBuilder private var content: some View {
        if model.loadingLeftovers {
            ScanningState(title: "Buscando archivos relacionados...", detail: app.name)
        } else {
            VStack(spacing: 0) {
                if model.selectedAppRunning {
                    Label("La app está abierta. Ciérrala antes de desinstalar.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).padding(.horizontal, 20).padding(.top, 12)
                }
                List {
                    Section("Aplicación") {
                        HStack {
                            Image(nsImage: IconStore.icon(for: app.url.path)).resizable().frame(width: 24, height: 24)
                            Text(app.name)
                            Spacer()
                            Text(ByteFormat.string(model.sizes[app.id] ?? 0)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Section(pluralized(model.leftovers.count, "archivo relacionado", "archivos relacionados")) {
                        if model.leftovers.isEmpty { Text("Sin archivos residuales conocidos").foregroundStyle(.secondary) }
                        ForEach(model.leftovers) { item in ItemRow(item: item, isOn: leftoverBinding(item)) }
                    }
                }.listStyle(.inset)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Total: \(ByteFormat.string(totalSelected))").foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button("Cancelar") { model.selectedApp = nil }.keyboardShortcut(.cancelAction)
            if model.uninstalling { ProgressView().controlSize(.small) }
            Button("Desinstalar") { confirming = true }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(model.selectedAppRunning || model.uninstalling || model.loadingLeftovers)
        }.padding(20)
    }

    private var permissionPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 7) {
                Text("macOS bloqueó la eliminación").font(.headline)
                Text("Para desinstalar otras apps, macOS exige autorizar a MyCleanUp en Gestión de apps. Activa MyCleanUp y reintenta.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Abrir Ajustes") { openAppManagementSettings() }.buttonStyle(.bordered)
                    Button("Reintentar") { model.confirmUninstall() }
                        .buttonStyle(.borderedProminent).tint(.orange).disabled(model.uninstalling)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.orange.opacity(0.35)))
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func openAppManagementSettings() {
        let workspace = NSWorkspace.shared
        if let appManagement = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"),
           workspace.open(appManagement) { return }
        if let privacy = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            workspace.open(privacy)
        }
    }

    private var totalSelected: Int64 {
        (model.sizes[app.id] ?? 0) + model.leftovers.filter { model.leftoverSelection.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    private func leftoverBinding(_ item: CleanableItem) -> Binding<Bool> {
        Binding(get: { model.leftoverSelection.contains(item.id) }, set: {
            if $0 { model.leftoverSelection.insert(item.id) } else { model.leftoverSelection.remove(item.id) }
        })
    }
}
