import SwiftUI
import AppKit

struct LargeFilesView: View {
    @ObservedObject var model: LargeFilesModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            controls
            content
        }
        .navigationTitle("Archivos grandes")
        .alert("¿Mover \(pluralized(model.selectedItems.count, "elemento", "elementos")) a la Papelera?", isPresented: $confirming) {
            Button("Mover a la Papelera", role: .destructive) { model.moveToTrash() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Podrás recuperarlos desde la Papelera mientras no la vacíes.") }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Text("Tamaño mínimo").fontWeight(.medium)
            Picker("Tamaño mínimo", selection: $model.minimumSize) {
                ForEach(model.presets, id: \.self) { size in Text(presetName(size)).tag(size) }
            }.labelsHidden().pickerStyle(.segmented).frame(width: 350)
            Spacer()
            if let outcome = model.lastOutcome { OutcomeBanner(outcome: outcome, verb: "Se movieron a la Papelera") }
            Button("Analizar") { model.scan() }.buttonStyle(.borderedProminent).tint(Theme.accent).disabled(model.phase == .scanning || model.phase == .cleaning)
        }.padding(20)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            CenteredState(icon: "shippingbox.fill", title: "Encuentra archivos grandes",
                          subtitle: "Localiza archivos que ocupan más espacio. macOS puede pedir permiso para acceder a Escritorio, Documentos y Descargas.",
                          buttonTitle: "Analizar", action: model.scan)
        case .scanning:
            ScanningState(title: "Buscando archivos grandes...", detail: model.progressText)
        case .done, .cleaning:
            results
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(pluralized(model.items.count, "archivo", "archivos")) · \(ByteFormat.string(model.totalSize))").font(.headline)
                Spacer()
                Text("Los archivos se mueven a la Papelera, no se eliminan definitivamente.").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.bottom, 10)
            List(model.items) { item in
                HStack(spacing: 10) {
                    Image(nsImage: IconStore.icon(for: item.url.path)).resizable().frame(width: 24, height: 24)
                    ItemRow(item: item, isOn: itemBinding(item))
                }
            }.listStyle(.inset)
            SelectionBar(count: model.selectedItems.count, size: model.selectedSize,
                         actionTitle: "Mover a la Papelera", busy: model.phase == .cleaning) { confirming = true }
        }
    }

    private func itemBinding(_ item: CleanableItem) -> Binding<Bool> {
        Binding(get: { model.selection.contains(item.id) }, set: {
            if $0 { model.selection.insert(item.id) } else { model.selection.remove(item.id) }
        })
    }

    private func presetName(_ bytes: Int64) -> String {
        if bytes == 1024 * 1_048_576 { return "1 GB" }
        return "\(bytes / 1_048_576) MB"
    }
}
