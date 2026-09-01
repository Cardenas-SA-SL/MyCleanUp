import SwiftUI

struct JunkView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var model: JunkModel
    @State private var expanded = Set<String>()
    @State private var confirming = false

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                CenteredState(icon: "sparkles", title: "Encuentra basura del sistema",
                              subtitle: "Analiza cachés, registros y archivos temporales de desarrollo que puedes eliminar con seguridad.",
                              buttonTitle: "Analizar", action: model.scan)
            case .scanning:
                ScanningState(title: "Analizando tu Mac...", detail: model.progressPath)
            case .done, .cleaning:
                results
            }
        }
        .navigationTitle("Limpieza del sistema")
        .alert("¿Eliminar \(pluralized(model.selectedItems.count, "elemento", "elementos")) (\(ByteFormat.string(model.selectedSize)))?", isPresented: $confirming) {
            Button("Eliminar", role: .destructive) { model.clean(); appState.stats.refresh() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Los archivos se eliminarán de forma definitiva. Las apps volverán a crear los cachés que necesiten.")
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            header
            List {
                ForEach(model.categories) { category in categoryGroup(category) }
            }.listStyle(.inset)
            SelectionBar(count: model.selectedItems.count, size: model.selectedSize,
                         actionTitle: "Limpiar", busy: model.phase == .cleaning) { confirming = true }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Se encontraron \(ByteFormat.string(model.totalFound))").font(.title2.bold())
            Spacer()
            if let outcome = model.lastOutcome { OutcomeBanner(outcome: outcome) }
            Button("Volver a analizar") { model.scan() }.buttonStyle(.bordered).disabled(model.phase == .cleaning)
        }.padding(20)
    }

    private func categoryGroup(_ category: JunkCategory) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(category.id) },
            set: { if $0 { expanded.insert(category.id) } else { expanded.remove(category.id) } }
        )) {
            ForEach(category.items) { item in
                ItemRow(item: item, isOn: itemBinding(item)).padding(.leading, 32)
            }
        } label: {
            HStack(spacing: 12) {
                Toggle("", isOn: categoryBinding(category)).labelsHidden().toggleStyle(.checkbox)
                TintedIcon(symbol: category.icon, color: Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title).font(.headline)
                    Text(category.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(pluralized(category.items.count, "elemento", "elementos")).font(.caption).foregroundStyle(.secondary)
                Text(ByteFormat.string(category.totalSize)).fontWeight(.semibold).monospacedDigit().frame(minWidth: 80, alignment: .trailing)
            }.padding(.vertical, 6)
        }
    }

    private func itemBinding(_ item: CleanableItem) -> Binding<Bool> {
        Binding(get: { model.selection.contains(item.id) }, set: {
            if $0 { model.selection.insert(item.id) } else { model.selection.remove(item.id) }
        })
    }

    private func categoryBinding(_ category: JunkCategory) -> Binding<Bool> {
        Binding(get: { category.items.allSatisfy { model.selection.contains($0.id) } }, set: { enabled in
            let ids = Set(category.items.map(\.id))
            if enabled { model.selection.formUnion(ids) } else { model.selection.subtract(ids) }
        })
    }
}
