/// A model as transcripts name it (`claude-opus-5-5`).
public struct ModelID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Claude Code writes this for messages it makes up itself; they never carry real usage.
    public static let synthetic = ModelID(rawValue: "<synthetic>")

    private static let families = ["opus", "sonnet", "haiku", "fable"]

    /// The short name the interface shows ("opus"); an unknown model shows its whole id.
    public var family: String {
        guard rawValue.hasPrefix("claude-") else { return rawValue }
        return Self.families.first { rawValue.contains("-\($0)") } ?? rawValue
    }
}

/// What a model costs, in USD per million tokens, and how much context it holds.
public struct ModelPricing: Equatable, Sendable {
    public var contextWindow: Int
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var cacheWrite5m: Double
    public var cacheWrite1h: Double

    public init(
        contextWindow: Int, input: Double, output: Double, cacheRead: Double, cacheWrite5m: Double,
        cacheWrite1h: Double
    ) {
        self.contextWindow = contextWindow
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }
}

/// The TOML's `[observatory.models."<id>"]`: any field it gives replaces the default one.
public struct ModelPricingOverride: Equatable, Sendable {
    public var contextWindow: Int?
    public var input: Double?
    public var output: Double?
    public var cacheRead: Double?
    public var cacheWrite5m: Double?
    public var cacheWrite1h: Double?

    public init(
        contextWindow: Int? = nil, input: Double? = nil, output: Double? = nil, cacheRead: Double? = nil,
        cacheWrite5m: Double? = nil, cacheWrite1h: Double? = nil
    ) {
        self.contextWindow = contextWindow
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    func applied(to base: ModelPricing) -> ModelPricing {
        ModelPricing(
            contextWindow: contextWindow ?? base.contextWindow, input: input ?? base.input,
            output: output ?? base.output, cacheRead: cacheRead ?? base.cacheRead,
            cacheWrite5m: cacheWrite5m ?? base.cacheWrite5m, cacheWrite1h: cacheWrite1h ?? base.cacheWrite1h)
    }

    /// A model the defaults do not know needs every field.
    var complete: ModelPricing? {
        guard let contextWindow, let input, let output, let cacheRead, let cacheWrite5m, let cacheWrite1h else {
            return nil
        }
        return ModelPricing(
            contextWindow: contextWindow, input: input, output: output, cacheRead: cacheRead,
            cacheWrite5m: cacheWrite5m, cacheWrite1h: cacheWrite1h)
    }
}

/// Prices and context windows per model. The defaults are Anthropic's list prices of 2026-11-03 (cache writes are
/// 1.25× the input for 5 minutes and 2× for an hour); the TOML can override them.
public struct ModelCatalog: Equatable, Sendable {
    private var pricings: [ModelID: ModelPricing]

    private static let million = 1_000_000

    public static let standard = ModelCatalog(pricings: [
        "claude-fable-5-2": ModelPricing(
            contextWindow: million, input: 8, output: 40, cacheRead: 0.20, cacheWrite5m: 10, cacheWrite1h: 16),
        "claude-fable-5-1": ModelPricing(
            contextWindow: million, input: 10, output: 50, cacheRead: 0.25, cacheWrite5m: 12.50, cacheWrite1h: 20),
        "claude-fable-5": ModelPricing(
            contextWindow: million, input: 10, output: 50, cacheRead: 1.00, cacheWrite5m: 12.50, cacheWrite1h: 20),
        "claude-opus-5-5": ModelPricing(
            contextWindow: million, input: 4, output: 20, cacheRead: 0.20, cacheWrite5m: 5, cacheWrite1h: 8),
        "claude-opus-5": ModelPricing(
            contextWindow: million, input: 5, output: 25, cacheRead: 0.50, cacheWrite5m: 6.25, cacheWrite1h: 10),
        "claude-opus-4-8": ModelPricing(
            contextWindow: million, input: 5, output: 25, cacheRead: 0.50, cacheWrite5m: 6.25, cacheWrite1h: 10),
        "claude-opus-4-7": ModelPricing(
            contextWindow: million, input: 5, output: 25, cacheRead: 0.50, cacheWrite5m: 6.25, cacheWrite1h: 10),
        "claude-opus-4-6": ModelPricing(
            contextWindow: million, input: 5, output: 25, cacheRead: 0.50, cacheWrite5m: 6.25, cacheWrite1h: 10),
        "claude-sonnet-5-5": ModelPricing(
            contextWindow: million, input: 2, output: 10, cacheRead: 0.10, cacheWrite5m: 2.50, cacheWrite1h: 4),
        "claude-sonnet-5": ModelPricing(
            contextWindow: million, input: 2, output: 10, cacheRead: 0.20, cacheWrite5m: 2.50, cacheWrite1h: 4),
        "claude-sonnet-4-6": ModelPricing(
            contextWindow: million, input: 3, output: 15, cacheRead: 0.30, cacheWrite5m: 3.75, cacheWrite1h: 6),
        "claude-haiku-5-5": ModelPricing(
            contextWindow: million, input: 0.10, output: 0.50, cacheRead: 0.01, cacheWrite5m: 0.125, cacheWrite1h: 0.20),
        "claude-haiku-4-5": ModelPricing(
            contextWindow: 200_000, input: 1, output: 5, cacheRead: 0.10, cacheWrite5m: 1.25, cacheWrite1h: 2),
    ])

    private init(pricings: [String: ModelPricing]) {
        self.pricings = Dictionary(uniqueKeysWithValues: pricings.map { (ModelID(rawValue: $0.key), $0.value) })
    }

    private init(byID pricings: [ModelID: ModelPricing]) {
        self.pricings = pricings
    }

    /// Tries the exact id, then without a bracketed suffix (`[1m]`), then without a date suffix (`-20251001`).
    public func pricing(for model: ModelID) -> ModelPricing? {
        candidates(for: model.rawValue).lazy.compactMap { pricings[ModelID(rawValue: $0)] }.first
    }

    private func candidates(for id: String) -> [String] {
        let withoutBracket = id.split(separator: "[", maxSplits: 1).first.map(String.init) ?? id
        return [id, withoutBracket, Self.droppingDate(withoutBracket)]
    }

    private static let dateSuffixLength = 9  // "-YYYYMMDD"

    private static func droppingDate(_ id: String) -> String {
        let suffix = id.suffix(dateSuffixLength)
        guard suffix.first == "-", suffix.dropFirst().allSatisfy(\.isNumber) else { return id }
        return String(id.dropLast(dateSuffixLength))
    }

    /// Known models take the given fields over their defaults; unknown ones are added only when complete.
    public func overriding(_ overrides: [ModelID: ModelPricingOverride]) -> ModelCatalog {
        var updated = pricings
        for (model, change) in overrides {
            if let base = pricing(for: model) {
                updated[model] = change.applied(to: base)
            } else if let full = change.complete {
                updated[model] = full
            }
        }
        return ModelCatalog(byID: updated)
    }
}
