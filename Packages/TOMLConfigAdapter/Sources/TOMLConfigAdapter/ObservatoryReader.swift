import SmaltiCore

/// `[observatory.models."<id>"]`: `context`, `input`, `output`, `cache_read`, `cache_write_5m`, `cache_write_1h`
/// (USD per million tokens). A known model takes any subset over its defaults; a new one needs all six.
enum ObservatoryReader {
    private static let modelsKey = "models"
    private static let contextKey = "context"
    private static let rateKeys = ["input", "output", "cache_read", "cache_write_5m", "cache_write_1h"]

    static func read(_ section: TOMLSection) throws(ConfigError) -> ObservatorySettings {
        try section.rejectUnknownKeys(allowed: [modelsKey])
        guard let models = try section.section(modelsKey) else { return .standard }
        var overrides: [ModelID: ModelPricingOverride] = [:]
        for id in models.keysInFileOrder {
            guard let table = try models.section(id) else { continue }
            let model = ModelID(rawValue: id)
            let change = try override(in: table)
            if ModelCatalog.standard.pricing(for: model) == nil {
                try requireAllKeys(of: table, at: id, in: models)
            }
            overrides[model] = change
        }
        return ObservatorySettings(models: overrides)
    }

    private static func override(in table: TOMLSection) throws(ConfigError) -> ModelPricingOverride {
        try table.rejectUnknownKeys(allowed: Set([contextKey] + rateKeys))
        var rates: [String: Double] = [:]
        for key in rateKeys {
            rates[key] = try rate(key, in: table)
        }
        return ModelPricingOverride(
            contextWindow: try context(in: table), input: rates["input"], output: rates["output"],
            cacheRead: rates["cache_read"], cacheWrite5m: rates["cache_write_5m"], cacheWrite1h: rates["cache_write_1h"]
        )
    }

    private static func rate(_ key: String, in table: TOMLSection) throws(ConfigError) -> Double? {
        guard let value = try table.number(key) else { return nil }
        guard value.isFinite, value >= 0 else { throw table.error(at: key, .notNegative) }
        return value
    }

    private static func context(in table: TOMLSection) throws(ConfigError) -> Int? {
        guard let value = try table.number(contextKey) else { return nil }
        guard value.isFinite, value > 0, value.rounded() == value, value < Double(Int.max) else {
            throw table.error(at: contextKey, .expectedPositiveInteger)
        }
        return Int(value)
    }

    private static func requireAllKeys(of table: TOMLSection, at id: String, in models: TOMLSection)
        throws(ConfigError)
    {
        let written = Set(table.keysInFileOrder)
        let missing = ([contextKey] + rateKeys).filter { !written.contains($0) }
        guard !missing.isEmpty else { return }
        throw models.error(at: id, .missingKeys(missing))
    }
}
