import SwiftUI
import AppKit

func pluralized(_ count: Int, _ singular: String, _ plural: String) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "es")
    formatter.numberStyle = .decimal
    let number = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    return "\(number) \(count == 1 ? singular : plural)"
}

struct CenteredState: View {
    let icon: String
    let title: String
    let subtitle: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.gradient).frame(width: 96, height: 96)
                Image(systemName: icon).font(.system(size: 39, weight: .semibold)).foregroundStyle(.white)
            }
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action).buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

struct ScanningState: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 540)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

struct SelectionBar: View {
    let count: Int
    let size: Int64
    let actionTitle: String
    let busy: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(pluralized(count, "seleccionado", "seleccionados")) · \(ByteFormat.string(size))").foregroundStyle(.secondary)
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.accent)
                .disabled(count == 0 || busy)
        }
        .padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
    }
}

struct OutcomeBanner: View {
    let outcome: CleanOutcome
    var verb = "Se liberaron"
    @State private var showingFailures = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: outcome.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(outcome.failures.isEmpty ? .green : .orange)
            Text(message).font(.callout.weight(.medium))
            if !outcome.failures.isEmpty {
                Button("Detalles") { showingFailures.toggle() }.buttonStyle(.link)
                    .popover(isPresented: $showingFailures) { failureList }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background((outcome.failures.isEmpty ? Color.green : Color.orange).opacity(0.12), in: Capsule())
    }

    private var message: String {
        if outcome.failures.isEmpty { return "\(verb) \(ByteFormat.string(outcome.freedBytes))" }
        if outcome.failures.count == 1 { return "Quedó 1 elemento con error" }
        return "Quedaron \(pluralized(outcome.failures.count, "elemento", "elementos")) con errores"
    }

    private var failureList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(outcome.failures.enumerated()), id: \.offset) { _, failure in
                    HStack(alignment: .top, spacing: 8) {
                        if failure.esPermiso {
                            Image(systemName: "lock.fill").foregroundStyle(.orange)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(failure.path).font(.caption).lineLimit(2).truncationMode(.middle)
                            Text(failure.message).font(.caption).foregroundStyle(.secondary)
                            if failure.esPermiso {
                                Text("Autoriza a MyCleanUp en Gestión de apps y reintenta.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }.padding(16)
        }.frame(width: 390, height: 240)
    }
}

struct ItemRow: View {
    let item: CleanableItem
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isOn).labelsHidden()
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).lineLimit(1)
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let modified = item.modified {
                Text(Fmt.date.string(from: modified)).font(.caption).foregroundStyle(.secondary)
            }
            Text(ByteFormat.string(item.size)).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 76, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        }
    }
}

enum IconStore {
    private static let cache = NSCache<NSString, NSImage>()
    static func icon(for path: String) -> NSImage {
        if let image = cache.object(forKey: path as NSString) { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 64, height: 64)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

struct TintedIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(color)
            .frame(width: 38, height: 38).background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
    }
}
