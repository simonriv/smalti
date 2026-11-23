import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("ObserveAgents")
@MainActor
struct ObserveAgentsTests {
    private typealias F = ObservatoryFixtures
    private let now = F.date("2026-11-18 10:42")

    private func make(
        transcripts: FakeAgentTranscripts = FakeAgentTranscripts(), live: FakeLiveAgents = FakeLiveAgents(),
        system: FakeSystemMetrics = FakeSystemMetrics()
    ) -> ObserveAgents {
        ObserveAgents(
            ObservatorySources(
                transcripts: transcripts, live: live, localModels: FakeLocalModels(), system: system,
                catalog: .standard, home: F.home))
    }

    @Test func snapshotAsksForThirtyDays() async {
        let transcripts = FakeAgentTranscripts()

        _ = await make(transcripts: transcripts).snapshot(panes: [], now: now)

        #expect(await transcripts.requestedSince == [now.addingTimeInterval(-30 * 86_400)])
    }

    @Test func snapshotCarriesSourcesAndPanes() async {
        let session = F.session("s", [F.turn("1", at: now)])
        let running = F.running("s", startedAt: now)
        let pane = F.paneAgent("s", state: .working, startedAt: now)

        let snapshot = await make(
            transcripts: FakeAgentTranscripts(sessions: [session]), live: FakeLiveAgents(running: [running])
        ).snapshot(panes: [pane], now: now)

        #expect(snapshot.activity.sessions == [session])
        #expect(snapshot.running == [running])
        #expect(snapshot.panes == [pane])
        #expect(snapshot.home == F.home)
        #expect(snapshot.lastError == nil)
    }

    @Test func systemSamplingKeepsSixtySamples() async {
        let system = FakeSystemMetrics()
        let observe = make(system: system)

        for index in 0..<65 {
            system.next = SystemSample(
                cpu: .value(Double(index)), gpu: index.isMultiple(of: 2) ? .value(1) : .unavailable,
                memoryUsed: .unavailable, memoryTotal: 1, agentsMemory: .unavailable, pressure: .unavailable,
                machineName: "Mac")
            observe.sampleSystem()
        }
        let snapshot = await observe.snapshot(panes: [], now: now)

        #expect(snapshot.cpuHistory.count == 60)
        #expect(snapshot.cpuHistory.last == 64)
        #expect(snapshot.gpuHistory.allSatisfy { $0 == 1 })
    }

    @Test func systemSamplesAreIndependentOfTranscriptRefresh() async {
        let system = FakeSystemMetrics()
        let observe = make(system: system)
        observe.sampleSystem()

        _ = await observe.snapshot(panes: [], now: now)
        _ = await observe.snapshot(panes: [], now: now)

        #expect(system.requestedProcesses.count == 1)
    }

    @Test func firstSnapshotSamplesWhenNothingWasSampled() async {
        let system = FakeSystemMetrics()

        _ = await make(system: system).snapshot(panes: [], now: now)

        #expect(system.requestedProcesses.count == 1)
    }

    @Test func systemSamplingUsesTheLatestAgentProcesses() async {
        let system = FakeSystemMetrics()
        let observe = make(live: FakeLiveAgents(running: [F.running("s", pid: 777, startedAt: now)]), system: system)
        _ = await observe.snapshot(panes: [], now: now)

        observe.sampleSystem()

        #expect(system.requestedProcesses.last == [777])
    }

    @Test func transcriptErrorKeepsPreviousSessionsAndReports() async {
        let session = F.session("s", [F.turn("1", at: now)])
        let transcripts = FakeAgentTranscripts(sessions: [session])
        let observe = make(transcripts: transcripts)
        _ = await observe.snapshot(panes: [], now: now)
        await transcripts.fail(with: .unreadableRoot(path: "/Users/simon/.claude/projects", reason: "permiso denegado"))

        let snapshot = await observe.snapshot(panes: [], now: now)

        #expect(snapshot.activity.sessions == [session])
        #expect(
            snapshot.lastError
                == "No se pudieron leer los transcripts de /Users/simon/.claude/projects: permiso denegado")
    }

    @Test func unknownStatusesAreCollected() async {
        let observe = make(live: FakeLiveAgents(running: [F.running("s", status: "thinking", startedAt: now)]))

        _ = await observe.snapshot(panes: [], now: now)

        #expect(observe.unknownStatuses == ["thinking"])
    }
}

@Suite("Observatory port contracts")
struct ObservatoryContractTests {
    private typealias F = ObservatoryFixtures

    @Test func fakeTranscriptsHonourTheContract() async {
        let now = F.date("2026-11-18 10:42")
        let fake = FakeAgentTranscripts(sessions: [F.session("s", [F.turn("1", at: now)])])

        await AgentTranscriptsContract.verify(fake, since: now.addingTimeInterval(-3_600))
    }

    @Test func fakeLiveAgentsHonourTheContract() async {
        await LiveAgentsContract.verify(FakeLiveAgents(running: [F.running("s", pid: 41, startedAt: .now)])) {
            $0 == 41
        }
    }

    @Test func fakeLocalModelsHonourTheContract() async {
        await LocalModelsContract.verify(FakeLocalModels())
        await LocalModelsContract.verify(
            FakeLocalModels(
                report: .available(
                    loaded: [
                        LocalModel(
                            name: "qwen3.5:9b", quantization: nil, bytes: 6_100_000_000, vramBytes: nil,
                            contextLength: nil, downloadedAt: nil)
                    ], onDisk: [])))
    }
}

/// Indexes in two steps, like the real adapter's first read (today first, the rest later).
private actor SteppedTranscripts: AgentTranscripts {
    private var calls = 0

    func activity(since: Date) async throws(TranscriptError) -> TranscriptActivity {
        calls += 1
        return TranscriptActivity(sessions: [], indexedSince: calls < 3 ? since.addingTimeInterval(86_400) : since)
    }
}

@Suite("Observatory contract settling")
struct ObservatoryContractSettlingTests {
    @Test func contractWaitsForAnAdapterThatIndexesInSteps() async {
        await AgentTranscriptsContract.verify(SteppedTranscripts(), since: Date(timeIntervalSince1970: 1_795_000_000))
    }
}
