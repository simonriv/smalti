/// Tokens of one or more model replies, split the way the API bills them.
public struct TokenUsage: Codable, Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite5m: Int
    public var cacheWrite1h: Int

    public init(input: Int, output: Int, cacheRead: Int, cacheWrite5m: Int, cacheWrite1h: Int) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    public static let zero = TokenUsage(input: 0, output: 0, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)

    /// "Tokens entrada" of the board and of the closing criterion: everything the model read, cached or not.
    public var inputTotal: Int { input + cacheRead + cacheWrite5m + cacheWrite1h }

    /// Share of the input read from the cache ("71% desde caché"); nil when nothing was read.
    public var cacheShare: Double? {
        inputTotal == 0 ? nil : Double(cacheRead) / Double(inputTotal)
    }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input, output: lhs.output + rhs.output, cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m, cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h)
    }
}
