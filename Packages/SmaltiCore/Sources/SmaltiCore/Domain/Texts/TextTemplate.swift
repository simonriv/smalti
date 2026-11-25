/// F7.7: a catalog phrase with named placeholders, "Aprobar “{quote}” en {workspace}". Both languages of a field
/// share the same placeholders (the catalog test checks it).
public struct TextTemplate: Sendable, Equatable, ExpressibleByStringLiteral {
    public let raw: String

    public init(_ raw: String) {
        self.raw = raw
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// The names between braces: letters, digits and underscores only, so "{ x }" and "{}" are plain text.
    public var placeholders: Set<String> {
        Set(pieces.compactMap { if case .placeholder(let name) = $0 { name } else { nil } })
    }

    /// Fills each placeholder once, left to right; a value is never read again as a template. A placeholder with
    /// no value stays as written.
    public func callAsFunction(_ values: KeyValuePairs<String, String>) -> String {
        filled(Dictionary(values.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first }))
    }

    func filled(_ lookup: [String: String]) -> String {
        pieces.map { piece in
            switch piece {
            case .text(let text): text
            case .placeholder(let name): lookup[name] ?? "{\(name)}"
            }
        }.joined()
    }

    private enum Piece {
        case text(String)
        case placeholder(String)
    }

    private var pieces: [Piece] {
        var result: [Piece] = []
        var rest = Substring(raw)
        while let open = rest.firstIndex(of: "{") {
            guard let close = rest[open...].firstIndex(of: "}") else { break }
            let name = rest[rest.index(after: open)..<close]
            if Self.isName(name) {
                result.append(.text(String(rest[..<open])))
                result.append(.placeholder(String(name)))
            } else {
                result.append(.text(String(rest[...close])))
            }
            rest = rest[rest.index(after: close)...]
        }
        result.append(.text(String(rest)))
        return result
    }

    private static func isName(_ name: Substring) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
