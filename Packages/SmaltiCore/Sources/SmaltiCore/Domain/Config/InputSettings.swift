/// `[input]` in the TOML: F4's switches, history size and generator timeout.
public struct InputSettings: Equatable, Sendable {
    public static let historyLimitRange = 1...1_000_000
    /// Milliseconds.
    public static let generatorTimeoutRange = 100...10_000

    public var isEnabled: Bool
    public var hasPredictions: Bool
    public var hasCompletions: Bool
    public var historyLimit: Int
    public var generatorTimeout: Duration

    public init(
        isEnabled: Bool, hasPredictions: Bool, hasCompletions: Bool, historyLimit: Int, generatorTimeout: Duration
    ) {
        self.isEnabled = isEnabled
        self.hasPredictions = hasPredictions
        self.hasCompletions = hasCompletions
        self.historyLimit = historyLimit
        self.generatorTimeout = generatorTimeout
    }

    public static let standard = InputSettings(
        isEnabled: true, hasPredictions: true, hasCompletions: true, historyLimit: 100_000,
        generatorTimeout: .milliseconds(1_000))
}
