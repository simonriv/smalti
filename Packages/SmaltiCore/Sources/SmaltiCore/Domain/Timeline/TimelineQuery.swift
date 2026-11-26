/// What the user typed in the timeline's search, folded to compare without case or accents (spec F9, section 4).
public struct TimelineQuery: Equatable, Sendable {
    /// Shorter plain runs match too much raw JSON to be worth a prefilter.
    static let minimumNeedle = 3

    public let raw: String
    public let folded: String

    public init(_ raw: String) {
        self.raw = raw
        folded = TextFolding.fold(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public var isEmpty: Bool { folded.isEmpty }

    /// The longest piece of the folded query that JSON writes as it is (no `"`, `\\` or control characters), as
    /// UTF-8, for the adapters' byte prefilter (they fold the file the same way); empty (every line is decoded) when
    /// it is shorter than 3.
    public var needle: [UInt8] {
        let pieces = folded.split(omittingEmptySubsequences: false) {
            $0 == "\"" || $0 == "\\" || $0.isNewline || $0 == "\t"
        }
        let longest = pieces.max { $0.count < $1.count } ?? ""
        return longest.count >= Self.minimumNeedle ? Array(String(longest).utf8) : []
    }
}

/// Lowercase without combining marks, character by character (no `Locale`: the domain stays language-neutral).
enum TextFolding {
    static func fold(_ text: String) -> String {
        String(text.map(fold))
    }

    static func fold(_ character: Character) -> Character {
        let scalars = String(character).lowercased().decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { !$0.properties.isGraphemeExtend }
        return scalars.isEmpty ? character : Character(String(String.UnicodeScalarView(scalars)))
    }
}

/// Finds a query in a visible text and cuts a snippet around it.
public enum TimelineMatch {
    /// Without case or accents, by Foundation's comparison (fast on long outputs; no locale).
    public static func find(_ query: TimelineQuery, in text: String) -> Range<String.Index>? {
        let needle = query.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive])
    }

    /// About `width` characters of one line around the match, with "…" where it was cut; the range is in the snippet.
    public static func snippet(_ text: String, around range: Range<String.Index>, width: Int) -> (
        String, Range<String.Index>
    ) {
        let matchLength = text.distance(from: range.lowerBound, to: range.upperBound)
        let side = max(0, (width - matchLength) / 2)
        let start = text.index(range.lowerBound, offsetBy: -side, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: side, limitedBy: text.endIndex) ?? text.endIndex
        let head = start > text.startIndex ? "…" : ""
        let tail = end < text.endIndex ? "…" : ""
        let flat = { (part: Substring) in part.replacingOccurrences(of: "\n", with: " ") }
        let before = head + flat(text[start..<range.lowerBound])
        let snippet = before + flat(text[range]) + flat(text[range.upperBound..<end]) + tail
        let lower = snippet.index(snippet.startIndex, offsetBy: before.count)
        return (snippet, lower..<snippet.index(lower, offsetBy: matchLength))
    }
}
