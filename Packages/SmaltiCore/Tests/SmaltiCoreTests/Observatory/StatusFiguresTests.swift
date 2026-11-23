import Foundation
import SmaltiCore
import Testing

@Suite("StatusFigures and PaneAgentDetail")
struct StatusFiguresTests {
    private typealias F = ObservatoryFixtures
    private let now = F.date("2026-11-18 10:42")

    private let qwen = LocalModel(
        name: "qwen3.5:9b", quantization: "Q4_K_M", bytes: 6_549_825_126, vramBytes: 6_549_825_126,
        contextLength: 65_536, downloadedAt: nil)

    @Test func statusShowsLoadedModelOnly() {
        let loaded = F.snapshot(sessions: [], localModels: .available(loaded: [qwen], onDisk: []), now: now)
        let idle = F.snapshot(sessions: [], localModels: .available(loaded: [], onDisk: [qwen]), now: now)

        #expect(StatusFigures.make(loaded, calendar: F.calendar()).localModel == "qwen3.5:9b · 6.1 GB")
        #expect(StatusFigures.make(idle, calendar: F.calendar()).localModel == nil)
    }

    @Test func statusShowsRamAndGpu() {
        let figures = StatusFigures.make(F.snapshot(sessions: [], now: now), calendar: F.calendar())

        #expect(figures.ram == "RAM 11.2 / 16 GB")
        #expect(figures.gpu == "GPU 38%")
    }

    @Test func statusGpuUnavailableText() {
        var system = F.system
        system.gpu = .unavailable
        system.memoryUsed = .unavailable

        let figures = StatusFigures.make(F.snapshot(sessions: [], system: system, now: now), calendar: F.calendar())

        #expect(figures.gpu == "GPU no disponible")
        #expect(figures.ram == "RAM no disponible")
    }

    @Test func todayTokensAddInputAndOutput() {
        let session = F.session(
            "s",
            [
                F.turn("1", at: F.date("2026-11-18 09:00"), output: 240_000, input: 1_000_000),
                F.turn("0", at: F.date("2026-11-17 09:00"), output: 999_999),
            ])

        let figures = StatusFigures.make(F.snapshot(sessions: [session], now: now), calendar: F.calendar())

        #expect(figures.todayTokens == "hoy 1.24M tokens")
    }

    @Test func paneDetailGivesFamilyAndContext() {
        let session = F.session("s", [F.turn("1", at: F.date("2026-11-18 09:00"), input: 410_000)])

        let detail = PaneAgentDetail.make(sessionID: "s", snapshot: F.snapshot(sessions: [session], now: now))

        #expect(detail == PaneAgentDetail(family: "opus", context: .percent(41)))
    }

    @Test func paneDetailForUnknownSessionIsUnavailable() {
        let detail = PaneAgentDetail.make(sessionID: "nope", snapshot: F.snapshot(sessions: [], now: now))

        #expect(detail == PaneAgentDetail(family: nil, context: .unavailable))
    }

    @Test func todayTokensWaitUntilTodayIsRead() {
        let session = F.session("s", [F.turn("1", at: F.date("2026-11-18 09:00"))])
        let snapshot = F.snapshot(sessions: [session], now: now, indexedSince: F.date("2026-11-18 08:00"))

        #expect(StatusFigures.make(snapshot, calendar: F.calendar()).todayTokens == "hoy …")
    }
}
