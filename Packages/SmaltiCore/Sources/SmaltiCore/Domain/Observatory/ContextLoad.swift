/// How full a session's context window is ("ctx 41%"), or unknown when the model or its window is.
public enum ContextLoad: Equatable, Sendable {
    case percent(Int)
    case unavailable

    /// From 75 % the bar turns amber (the board shows 41 % and 63 % in the accent, 78 % in amber).
    public static let highThreshold = 75

    public static func of(contextTokens: Int?, model: ModelID?, catalog: ModelCatalog) -> ContextLoad {
        guard let contextTokens, let model, let window = catalog.pricing(for: model)?.contextWindow, window > 0 else {
            return .unavailable
        }
        return .percent(Int((Double(contextTokens) * 100 / Double(window)).rounded()))
    }

    public var isHigh: Bool {
        guard case .percent(let value) = self else { return false }
        return value >= Self.highThreshold
    }
}
