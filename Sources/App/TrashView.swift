import SwiftUI

struct TrashView: View {
    @ObservedObject var model: TrashModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.gradient).frame(width: 96, height: 96)
                Image(systemName: "trash.fill").font(.system(size: 39, weight: .semibold)).foregroundStyle(.white)
            }
            Text(ByteFormat.string(model.size)).font(.largeTitle.bold()).monospacedDigit()
            Text("\(pluralized(model.count, "elemento", "elementos")) en la Papelera").foregroundStyle(.secondary)
            Text("Vaciar la Papelera elimina su contenido de forma definitiva.").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Actualizar") { model.refresh() }.buttonStyle(.bordered).controlSize(.large).disabled(model.working)
                if model.working { ProgressView().controlSize(.small) }
                Button("Vaciar Papelera") { confirming = true }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(.red)
                    .disabled(model.count == 0 || model.working)
            }
            if let outcome = model.lastOutcome { OutcomeBanner(outcome: outcome) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
        .navigationTitle("Papelera")
        .onAppear { model.refresh() }
        .alert("¿Vaciar la Papelera?", isPresented: $confirming) {
            Button("Vaciar Papelera", role: .destructive) { model.empty() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Esta acción es definitiva y no se puede deshacer.") }
    }
}
