import SwiftUI
import Combine
import AppKit

struct DashboardView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var stats: StatsModel
    @ObservedObject private var junk: JunkModel
    @ObservedObject private var trash: TrashModel
    @ObservedObject private var menuBar: MenuBarModel
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    init(appState: AppState) {
        self.appState = appState
        self.stats = appState.stats
        self.junk = appState.junk
        self.trash = appState.trash
        self.menuBar = appState.menuBar
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                statsCards
                junkSummary
            }
            .padding(24)
        }
        .navigationTitle("Panel de control")
        .onAppear { stats.refresh(); trash.refresh() }
        .onReceive(timer) { _ in stats.refreshMemory() }
        .onChange(of: junk.phase) { phase in
            if phase == .done { stats.refresh(); trash.refresh() }
        }
        .onReceive(menuBar.$optimizerState) { state in
            if case .result = state { stats.refresh() }
        }
    }

    private var hero: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 12) {
                Text(greeting).font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                Text("Recupera espacio y mantén tu Mac en forma.").font(.title3).foregroundStyle(.white.opacity(0.9))
                Button { junk.scan(); appState.section = .junk } label: {
                    Label("Analizar mi Mac", systemImage: "sparkles").fontWeight(.semibold)
                        .foregroundStyle(Theme.accent).padding(.horizontal, 18).padding(.vertical, 10)
                        .background(.white, in: Capsule())
                }.buttonStyle(.plain).padding(.top, 5)
            }
            Spacer()
            RingGauge(fraction: stats.disk?.usedFraction ?? 0)
        }
        .padding(28)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var greeting: String {
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "Hola 👋" : "Hola, \(first) 👋"
    }

    private var statsCards: some View {
        HStack(spacing: 16) {
            statCard(title: "Disco", icon: "internaldrive.fill", color: .blue,
                     value: stats.disk.map { ByteFormat.string($0.free) } ?? "N/D",
                     caption: stats.disk.map { "libres de \(ByteFormat.string($0.total))" } ?? "Capacidad no disponible",
                     valueColor: diskValueColor)
            memoryCard
            statCard(title: "Papelera", icon: "trash.fill", color: .orange,
                     value: ByteFormat.string(trash.size), caption: pluralized(trash.count, "elemento", "elementos"))
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func statCard(title: String, icon: String, color: Color, value: String,
                          caption: String, valueColor: Color = .primary) -> some View {
        HStack(alignment: .top, spacing: 13) {
            TintedIcon(symbol: icon, color: color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(value).font(.title2.bold()).foregroundStyle(valueColor).monospacedDigit()
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).card()
    }

    private var memoryCard: some View {
        HStack(alignment: .top, spacing: 13) {
            TintedIcon(symbol: "memorychip.fill", color: .green)
            VStack(alignment: .leading, spacing: 5) {
                Text("Memoria").font(.headline)
                Text(stats.memory.map { ByteFormat.string($0.used) } ?? "N/D")
                    .font(.title2.bold()).foregroundStyle(memoryValueColor).monospacedDigit()
                if let memory = stats.memory {
                    ProgressView(value: memory.fraction).tint(adaptiveHealthColor(memoryHealth(memory)))
                    HStack(spacing: 8) {
                        Text("de \(ByteFormat.string(memory.total)) en uso").font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        dashboardOptimizerControl
                    }
                } else {
                    HStack(spacing: 8) {
                        Text("Uso no disponible").font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        dashboardOptimizerControl
                    }
                }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).card()
    }

    @ViewBuilder private var dashboardOptimizerControl: some View {
        switch menuBar.optimizerState {
        case .idle:
            Button("Optimizar") { menuBar.optimize() }.buttonStyle(.bordered).controlSize(.small)
        case .running:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Optimizando...").font(.caption2).foregroundStyle(.secondary)
            }
        case .result(let result):
            Text(result.freedBytes < 32 * 1_048_576
                 ? "Ya estaba optimizada"
                 : "Se liberaron \(ByteFormat.string(result.freedBytes))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var junkSummary: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(Theme.gradient).frame(width: 44, height: 44)
                Image(systemName: "sparkles").foregroundStyle(.white).font(.title3.bold())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(junkSummaryTitle).font(.headline).foregroundStyle(junkSummaryColor)
                if junk.phase == .done { Text("Lista para revisar").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if junk.phase == .scanning {
                ProgressView().controlSize(.small)
                Text("Analizando...").foregroundStyle(.secondary)
            } else {
                Button(junk.phase == .done ? "Revisar y limpiar" : "Analizar") {
                    if junk.phase != .done { junk.scan() }
                    appState.section = .junk
                }.buttonStyle(.bordered).controlSize(.large)
            }
        }.card()
    }

    private var junkSummaryTitle: String {
        junk.phase == .done ? "\(ByteFormat.string(junk.totalFound)) de basura encontrada" : "Analiza tu Mac para encontrar archivos innecesarios"
    }

    private var diskValueColor: Color {
        guard let disk = stats.disk, disk.total > 0 else { return .primary }
        let fraction = Double(disk.free) / Double(disk.total)
        return adaptiveHealthColor(HealthAssessor.disk(freeFraction: fraction, freeBytes: disk.free))
    }

    private var memoryValueColor: Color {
        guard let memory = stats.memory else { return .primary }
        return adaptiveHealthColor(memoryHealth(memory))
    }

    private func memoryHealth(_ memory: MemoryStats) -> HealthLevel {
        guard memory.total > 0 else { return .critical }
        let available = max(0, memory.total - memory.used)
        return HealthAssessor.memory(availableFraction: Double(available) / Double(memory.total))
    }

    private var junkSummaryColor: Color {
        guard junk.phase == .done else { return .primary }
        return adaptiveHealthColor(HealthAssessor.junk(bytes: junk.totalFound))
    }

    private func adaptiveHealthColor(_ level: HealthLevel) -> Color {
        switch level {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

private struct RingGauge: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 12)
            Circle().trim(from: 0, to: fraction).stroke(.white, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(Int(fraction * 100)) %").font(.title.bold()).monospacedDigit()
                Text("usado").font(.caption)
            }.foregroundStyle(.white)
        }.frame(width: 148, height: 148).padding(4)
    }
}
