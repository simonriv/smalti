import SmaltiCore
import Testing

@Suite("CostEstimate and ContextLoad")
struct CostEstimateTests {
    private let opus = ModelID(rawValue: "claude-opus-5-5")
    private let sonnet = ModelID(rawValue: "claude-sonnet-5-5")
    private let million = 1_000_000

    @Test func costUsesAllFiveRates() {
        let usage = TokenUsage(
            input: million, output: million, cacheRead: million, cacheWrite5m: million, cacheWrite1h: million)

        let cost = CostEstimate.of([opus: usage], catalog: .standard)

        #expect(abs(cost.usd - 37.20) < 0.000_001)
        #expect(cost.unpricedModels.isEmpty)
    }

    @Test func costSkipsAndReportsUnpricedModel() {
        let unknown = ModelID(rawValue: "claude-unknown-9")
        let usage = TokenUsage(input: million, output: 0, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)

        let cost = CostEstimate.of([opus: usage, unknown: usage], catalog: .standard)

        #expect(abs(cost.usd - 4) < 0.000_001)
        #expect(cost.unpricedModels == [unknown])
    }

    @Test func costSumsAcrossModels() {
        let output = TokenUsage(input: 0, output: million, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)

        let cost = CostEstimate.of([opus: output, sonnet: output], catalog: .standard)

        #expect(abs(cost.usd - 30) < 0.000_001)
    }

    @Test func contextRoundsToNearestPercent() {
        #expect(ContextLoad.of(contextTokens: 415_000, model: opus, catalog: .standard) == .percent(42))
        #expect(ContextLoad.of(contextTokens: 414_999, model: opus, catalog: .standard) == .percent(41))
    }

    @Test func contextWithoutWindowIsUnavailable() {
        let unknown = ModelID(rawValue: "claude-unknown-9")

        #expect(ContextLoad.of(contextTokens: 1_000, model: unknown, catalog: .standard) == .unavailable)
        #expect(ContextLoad.of(contextTokens: nil, model: opus, catalog: .standard) == .unavailable)
        #expect(ContextLoad.of(contextTokens: 1_000, model: nil, catalog: .standard) == .unavailable)
    }

    @Test func contextAt75IsHigh() {
        #expect(ContextLoad.percent(75).isHigh)
    }

    @Test func contextAt74IsNotHigh() {
        #expect(!ContextLoad.percent(74).isHigh)
        #expect(!ContextLoad.unavailable.isHigh)
    }

    @Test func costIgnoresUnpricedModelWithoutTokens() {
        let cost = CostEstimate.of([.synthetic: .zero], catalog: .standard)

        #expect(cost.unpricedModels.isEmpty)
        #expect(cost.usd == 0)
    }
}
