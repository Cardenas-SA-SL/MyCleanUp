import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var model: MenuBarModel
    @ObservedObject private var junk: JunkModel
    @Environment(\.openWindow) private var openWindow

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    init(appState: AppState) {
        self.appState = appState
        self.model = appState.menuBar
        self.junk = appState.junk
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                diskCard
                memoryCard
                if model.battery.hasBattery { batteryCard }
                cpuCard
                networkCard
            }
            footer
        }
        .padding(16)
        .frame(width: 360)
        .background(menuBackground)
        .onAppear { model.startRefreshing() }
        .onDisappear { model.stopRefreshing() }
    }

    private var menuBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.23, green: 0.15, blue: 0.50), Color(red: 0.12, green: 0.08, blue: 0.25)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ).ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.gradient)
                Image(systemName: "sparkles").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            }.frame(width: 22, height: 22)
            Text("Resumen del Mac").font(.headline.bold()).foregroundStyle(.white)
            Spacer()
        }
    }

    private var diskCard: some View {
        MenuStatCard(title: "Disco", icon: "internaldrive.fill", minimumHeight: 142) {
            Text(model.disk.map { "\(ByteFormat.string($0.free)) libres" } ?? "N/D")
                .font(.headline).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
            Text(model.disk.map { "de \(ByteFormat.string($0.total))" } ?? "Capacidad no disponible")
                .font(.caption).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
            Spacer(minLength: 8)
            HStack {
                Spacer()
                WhiteCapsuleButton(title: "Limpiar") { openJunk() }
            }
        }
    }

    private var memoryCard: some View {
        MenuStatCard(title: "Memoria", icon: "memorychip.fill", minimumHeight: 142) {
            Text("\(ByteFormat.string(model.memoryAvailable)) disponibles")
                .font(.headline).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.78)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule().fill(.white.opacity(0.9))
                        .frame(width: proxy.size.width * memoryUsedFraction)
                }
            }.frame(height: 5)
            Spacer(minLength: 7)
            optimizerControl
        }
    }

    @ViewBuilder private var optimizerControl: some View {
        switch model.optimizerState {
        case .idle:
            HStack {
                Spacer()
                WhiteCapsuleButton(title: "Optimizar") { model.optimize() }
            }
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Optimizando...").font(.caption.weight(.medium)).foregroundStyle(.white)
            }
        case .result(let result):
            Text(optimizerResultText(result)).font(.caption.weight(.medium)).foregroundStyle(.white)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var batteryCard: some View {
        MenuStatCard(title: "Batería", icon: "battery.75", minimumHeight: 112) {
            Text("\(model.battery.percent) %").font(.headline).foregroundStyle(.white).monospacedDigit()
            Text(batteryCaption).font(.caption).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var cpuCard: some View {
        MenuStatCard(title: "CPU", icon: "cpu", minimumHeight: 112) {
            Text("Carga: \(Int((model.cpuLoad * 100).rounded())) %")
                .font(.headline).foregroundStyle(.white).monospacedDigit()
            Text(pluralized(model.coreCount, "núcleo", "núcleos"))
                .font(.caption).foregroundStyle(.white.opacity(0.68))
            Spacer(minLength: 0)
        }
    }

    private var networkCard: some View {
        MenuStatCard(title: "Red", icon: "wifi", minimumHeight: 112) {
            Text("↑ \(ByteFormat.string(model.netUp))/s").font(.headline).foregroundStyle(.white).monospacedDigit()
            Text("↓ \(ByteFormat.string(model.netDown))/s").font(.headline).foregroundStyle(.white).monospacedDigit()
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
            HStack(spacing: 8) {
                Button(action: openJunk) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundStyle(.white)
                        Text(footerText).font(.callout.weight(.medium)).foregroundStyle(.white).lineLimit(1)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer()
                Menu {
                    Button("Abrir MyCleanUp") { openMain(section: .dashboard, scanIfIdle: false) }
                    Divider()
                    Button("Salir de MyCleanUp") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "gearshape.fill").foregroundStyle(.white.opacity(0.82))
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
    }

    private var memoryUsedFraction: Double {
        guard model.memory.total > 0 else { return 0 }
        return min(1, max(0, Double(model.memory.used) / Double(model.memory.total)))
    }

    private var batteryCaption: String {
        if model.battery.isCharging { return "Cargando" }
        if model.battery.onACPower {
            return model.battery.percent >= 100 ? "Cargada" : "Con corriente"
        }
        guard let minutes = model.battery.minutesRemaining else { return "En batería" }
        return "\(minutes / 60)h \(minutes % 60)m restantes"
    }

    private var footerText: String {
        if junk.phase == .done { return "Limpia hasta \(ByteFormat.string(junk.totalFound)) de basura" }
        return "Analizar basura"
    }

    private func optimizerResultText(_ result: OptimizeResult) -> String {
        result.freedBytes < 32 * 1_048_576
            ? "Ya estaba optimizada"
            : "Se liberaron \(ByteFormat.string(result.freedBytes))"
    }

    private func openJunk() {
        openMain(section: .junk, scanIfIdle: true)
    }

    private func openMain(section: AppSection, scanIfIdle: Bool) {
        appState.section = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        if scanIfIdle, appState.junk.phase == .idle { appState.junk.scan() }
    }
}

private struct MenuStatCard<Content: View>: View {
    let title: String
    let icon: String
    let minimumHeight: CGFloat
    let content: Content

    init(title: String, icon: String, minimumHeight: CGFloat,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.minimumHeight = minimumHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.bold()).foregroundStyle(.white.opacity(0.82))
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.76))
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct WhiteCapsuleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(red: 0.23, green: 0.15, blue: 0.50))
            .buttonStyle(.plain)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(.white, in: Capsule())
    }
}
