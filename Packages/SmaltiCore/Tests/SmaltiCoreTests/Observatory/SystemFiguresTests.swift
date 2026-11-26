import Foundation
import SmaltiCore
import Testing

@Suite("SystemFigures and LocalModelsFigures")
struct SystemFiguresTests {
    private typealias F = ObservatoryFixtures
    private let now = F.date("2026-11-18 10:42")
    private let gib: UInt64 = 1_073_741_824

    private func model(_ name: String, bytes: UInt64, vram: UInt64? = nil, downloaded: Date? = nil) -> LocalModel {
        LocalModel(
            name: name, quantization: vram == nil ? nil : "Q4_K_M", bytes: bytes, vramBytes: vram,
            contextLength: vram == nil ? nil : 65_536, downloadedAt: downloaded)
    }

    private func sample(used: UInt64, agents: UInt64) -> SystemSample {
        SystemSample(
            cpu: .value(31), gpu: .value(38), memoryUsed: .value(used), memoryTotal: 16 * gib,
            agentsMemory: .value(agents), pressure: .value(.media), machineName: "MacBook Air M4")
    }

    @Test func memorySplitNamesModelAgentsAndRest() {
        let qwen = model("qwen3.5:9b", bytes: 6_549_825_126, vram: 6_549_825_126)
        let snapshot = F.snapshot(
            sessions: [], localModels: .available(loaded: [qwen], onDisk: []),
            system: sample(used: 12_025_908_428, agents: 3_758_096_384), now: now)

        let figures = SystemFigures.make(snapshot, copy: .spanish)

        #expect(figures.title == "Sistema · MacBook Air M4")
        #expect(figures.cpu == "31%")
        #expect(figures.gpu == "38%")
        #expect(figures.memory == "11.2 / 16 GB")
        #expect(figures.split == "modelo 6.1 · agentes 3.5 · resto 1.6 GB · presión media")
        #expect(abs(figures.shares.model - 6_549_825_126 / Double(16 * gib)) < 0.000_1)
        #expect(abs(figures.shares.agents - 3_758_096_384 / Double(16 * gib)) < 0.000_1)
        #expect(
            abs(figures.shares.rest - Double(12_025_908_428 - 6_549_825_126 - 3_758_096_384) / Double(16 * gib))
                < 0.000_1)
    }

    @Test func memorySplitOmitsModelWithoutOllama() {
        let snapshot = F.snapshot(sessions: [], system: sample(used: 8 * gib, agents: 2 * gib), now: now)

        let figures = SystemFigures.make(snapshot, copy: .spanish)

        #expect(figures.split == "agentes 2.0 · resto 6.0 GB · presión media")
        #expect(figures.shares.model == 0)
    }

    @Test func unavailablePartReadsNoDisponible() {
        let system = SystemSample(
            cpu: .unavailable, gpu: .unavailable, memoryUsed: .unavailable, memoryTotal: 16 * gib,
            agentsMemory: .unavailable, pressure: .unavailable, machineName: "Apple M4")

        let figures = SystemFigures.make(F.snapshot(sessions: [], system: system, now: now), copy: .spanish)

        #expect(figures.cpu == "no disponible")
        #expect(figures.gpu == "no disponible")
        #expect(figures.memory == "no disponible")
        #expect(figures.split == "no disponible")
    }

    @Test func restNeverNegative() {
        let qwen = model("qwen3.5:9b", bytes: 9 * gib, vram: 9 * gib)
        let snapshot = F.snapshot(
            sessions: [], localModels: .available(loaded: [qwen], onDisk: []),
            system: sample(used: 10 * gib, agents: 3 * gib), now: now)

        let figures = SystemFigures.make(snapshot, copy: .spanish)

        #expect(figures.split == "modelo 9.0 · agentes 3.0 · resto 0.0 GB · presión media")
        #expect(figures.shares.rest == 0)
    }

    @Test func loadedAndOnDiskRows() {
        let loaded = model("qwen3.5:9b", bytes: 6_549_825_126, vram: 6_549_825_126)
        let disk = model("nomic-embed-text", bytes: 287_309_824, downloaded: now.addingTimeInterval(-2 * 86_400))

        let figures = LocalModelsFigures.make(
            .available(loaded: [loaded], onDisk: [disk, loaded]), now: now, copy: .spanish)

        #expect(
            figures
                == .models([
                    .init(name: "qwen3.5:9b", status: "cargado", isLoaded: true, detail: "Q4_K_M · 6.1 GB · ctx 64K"),
                    .init(
                        name: "nomic-embed-text", status: "en disco", isLoaded: false,
                        detail: "274 MB · descargado hace 2 días"),
                ]))
    }

    @Test func ollamaUnavailableHasItsText() {
        #expect(LocalModelsFigures.make(.unavailable, now: now, copy: .spanish) == .message("Ollama no está corriendo"))
    }

    @Test func noModelsHasItsText() {
        #expect(
            LocalModelsFigures.make(.available(loaded: [], onDisk: []), now: now, copy: .spanish)
                == .message("Sin modelos locales"))
    }
}
