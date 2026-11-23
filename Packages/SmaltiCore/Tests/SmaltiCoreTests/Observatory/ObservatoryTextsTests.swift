import Foundation
import SmaltiCore
import Testing

@Suite("Observatory texts")
struct ObservatoryTextsTests {
    private typealias F = ObservatoryFixtures
    private let bogota = TimeZone(identifier: "America/Bogota") ?? .gmt
    private let at = Date(timeIntervalSince1970: 1_795_000_000)

    private func summary(
        working: Int = 2, waiting: Int = 1, failed: Int = 0, cacheShare: Int? = 71, peak: OutputPeak? = nil,
        unpriced: Set<ModelID> = []
    ) -> ObservatoryReport.Summary {
        ObservatoryReport.Summary(
            active: working + waiting + failed, working: working, waiting: waiting, failed: failed, input: 982_000,
            cacheShare: cacheShare, output: 61_400, peak: peak, cost: CostEstimate(usd: 18.4, unpricedModels: unpriced),
            isComplete: true)
    }

    @Test func sessionsLineCountsWorkingAndWaiting() {
        #expect(ObservatoryTexts.sessions(summary()) == "2 trabajando · 1 esperando")
    }

    @Test func sessionsLineAddsErrorsOnlyWhenThereAreSome() {
        #expect(ObservatoryTexts.sessions(summary(failed: 1)) == "2 trabajando · 1 esperando · 1 error")
    }

    @Test func cacheLineAndItsAbsence() {
        #expect(ObservatoryTexts.cache(summary()) == "71% desde caché")
        #expect(ObservatoryTexts.cache(summary(cacheShare: nil)) == "sin entrada")
    }

    @Test func peakLineHasRateAndTime() {
        let line = ObservatoryTexts.peak(summary(peak: OutputPeak(output: 4_800, at: at)), timeZone: bogota)

        #expect(line == "pico 4.8k/min · 06:06")
        #expect(ObservatoryTexts.peak(summary(), timeZone: bogota) == "sin salida")
    }

    @Test func costLineSaysItIsAnEstimate() {
        #expect(ObservatoryTexts.cost(summary()) == "estimado · incluido en tu plan")
    }

    @Test func costLineCountsUnpricedModels() {
        let one: Set<ModelID> = [ModelID(rawValue: "a")]
        let two: Set<ModelID> = [ModelID(rawValue: "a"), ModelID(rawValue: "b")]

        #expect(
            ObservatoryTexts.cost(summary(unpriced: one)) == "estimado · sin precio para 1 modelo"
        )
        #expect(
            ObservatoryTexts.cost(summary(unpriced: two))
                == "estimado · sin precio para 2 modelos")
    }

    private func tool(_ name: String, _ outcome: ToolOutcome) -> RecentTool {
        RecentTool(id: "t", name: name, summary: "", startedAt: at, outcome: outcome)
    }

    @Test func toolResultsFollowTheBoard() {
        #expect(
            ObservatoryTexts.result(of: tool("Bash", .succeeded(duration: 1.84)))
                == ToolResultText(text: "1.8s", isFailure: false))
        #expect(
            ObservatoryTexts.result(of: tool("Read", .succeeded(duration: 0.1)))
                == ToolResultText(text: "ok", isFailure: false))
        #expect(
            ObservatoryTexts.result(of: tool("Bash", .failed(exitCode: 1)))
                == ToolResultText(text: "exit 1", isFailure: true))
        #expect(
            ObservatoryTexts.result(of: tool("Edit", .failed(exitCode: nil)))
                == ToolResultText(text: "error", isFailure: true))
    }

    @Test func rowStatesUseTheTableWords() {
        #expect(
            [AgentStateKind.working, .waiting, .failed, .stopped].map(ObservatoryTexts.state) == [
                "trabajando", "te espera", "error", "detenida",
            ])
    }

    @Test func peakLabelOfTheChart() {
        #expect(ObservatoryTexts.chartPeak(OutputPeak(output: 4_800, at: at), timeZone: bogota) == "4.8k · 06:06")
    }
}
