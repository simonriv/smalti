/// `[observatory]` in the TOML: price and context-window overrides per model.
public struct ObservatorySettings: Equatable, Sendable {
    public var models: [ModelID: ModelPricingOverride]

    public init(models: [ModelID: ModelPricingOverride] = [:]) {
        self.models = models
    }

    public static let standard = ObservatorySettings()

    /// The default catalog with the TOML's overrides on top.
    public var catalog: ModelCatalog { ModelCatalog.standard.overriding(models) }
}
