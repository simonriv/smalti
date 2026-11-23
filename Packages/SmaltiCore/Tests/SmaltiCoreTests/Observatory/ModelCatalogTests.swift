import SmaltiCore
import Testing

@Suite("ModelCatalog")
struct ModelCatalogTests {
    private let catalog = ModelCatalog.standard

    @Test(arguments: [
        ("claude-opus-5-5", "opus"), ("claude-sonnet-5-5", "sonnet"), ("claude-haiku-4-5", "haiku"),
        ("claude-fable-5-2", "fable"), ("qwen3.5:9b", "qwen3.5:9b"),
    ])
    func familyComesFromModelID(id: String, family: String) {
        #expect(ModelID(rawValue: id).family == family)
    }

    @Test func standardHasOpusFiveFivePrices() {
        let pricing = catalog.pricing(for: ModelID(rawValue: "claude-opus-5-5"))

        #expect(
            pricing
                == ModelPricing(
                    contextWindow: 1_000_000, input: 4, output: 20, cacheRead: 0.20, cacheWrite5m: 5, cacheWrite1h: 8))
    }

    @Test func haikuFourFiveHasTwoHundredThousandWindow() {
        #expect(catalog.pricing(for: ModelID(rawValue: "claude-haiku-4-5"))?.contextWindow == 200_000)
    }

    @Test func fableVersionsHaveTheirOwnCacheReadPrice() {
        #expect(catalog.pricing(for: ModelID(rawValue: "claude-fable-5-1"))?.cacheRead == 0.25)
        #expect(catalog.pricing(for: ModelID(rawValue: "claude-fable-5"))?.cacheRead == 1.00)
    }

    @Test func pricingFallsBackWithoutBracketSuffix() {
        #expect(catalog.pricing(for: ModelID(rawValue: "claude-opus-5-5[1m]"))?.input == 4)
    }

    @Test func pricingFallsBackWithoutDateSuffix() {
        #expect(catalog.pricing(for: ModelID(rawValue: "claude-haiku-4-5-20251001"))?.input == 1)
    }

    @Test func unknownModelHasNoPricing() {
        #expect(catalog.pricing(for: ModelID(rawValue: "claude-unknown-9")) == nil)
    }

    @Test func overrideReplacesOnlyGivenFields() {
        let opus = ModelID(rawValue: "claude-opus-5-5")

        let edited = catalog.overriding([opus: ModelPricingOverride(output: 30)])

        #expect(edited.pricing(for: opus)?.output == 30)
        #expect(edited.pricing(for: opus)?.input == 4)
    }

    @Test func overrideAddsNewModel() {
        let local = ModelID(rawValue: "claude-next-1")
        let full = ModelPricingOverride(
            contextWindow: 500_000, input: 1, output: 2, cacheRead: 0.1, cacheWrite5m: 1.25, cacheWrite1h: 2)

        let edited = catalog.overriding([local: full])

        #expect(edited.pricing(for: local)?.contextWindow == 500_000)
    }

    @Test func incompleteOverrideOfUnknownModelAddsNothing() {
        let local = ModelID(rawValue: "claude-next-1")

        let edited = catalog.overriding([local: ModelPricingOverride(input: 1)])

        #expect(edited.pricing(for: local) == nil)
    }
}
