/// F7.7: a phrase with a count. English and Spanish both use the singular only for 1.
public struct PluralText: Sendable, Equatable {
    public let one: TextTemplate
    public let other: TextTemplate

    public init(one: TextTemplate, other: TextTemplate) {
        self.one = one
        self.other = other
    }

    /// `{count}` is always filled; `values` fills the rest.
    public func callAsFunction(_ count: Int, _ values: KeyValuePairs<String, String> = [:]) -> String {
        var lookup = Dictionary(values.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        lookup["count"] = String(count)
        return (count == 1 ? one : other).filled(lookup)
    }
}
