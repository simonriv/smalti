/// The API price of some usage. Smalti's user pays a subscription, so this is an estimate ("Equivalente API").
public struct CostEstimate: Equatable, Sendable {
    public let usd: Double
    /// Models with tokens but no price: their tokens add nothing and the card says so.
    public let unpricedModels: Set<ModelID>

    private static let tokensPerPriceUnit = 1_000_000.0

    public static func of(_ usage: [ModelID: TokenUsage], catalog: ModelCatalog) -> CostEstimate {
        var usd = 0.0
        var unpriced: Set<ModelID> = []
        for (model, tokens) in usage where tokens != .zero {
            guard let pricing = catalog.pricing(for: model) else {
                unpriced.insert(model)
                continue
            }
            usd += cost(of: tokens, at: pricing)
        }
        return CostEstimate(usd: usd, unpricedModels: unpriced)
    }

    private static func cost(of tokens: TokenUsage, at pricing: ModelPricing) -> Double {
        let perRate: [(Int, Double)] = [
            (tokens.input, pricing.input), (tokens.output, pricing.output), (tokens.cacheRead, pricing.cacheRead),
            (tokens.cacheWrite5m, pricing.cacheWrite5m), (tokens.cacheWrite1h, pricing.cacheWrite1h),
        ]
        return perRate.reduce(0) { $0 + Double($1.0) * $1.1 } / tokensPerPriceUnit
    }
}
