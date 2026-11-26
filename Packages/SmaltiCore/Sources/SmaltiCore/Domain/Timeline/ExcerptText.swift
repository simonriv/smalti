/// A transcript text as the timeline keeps it: the first `limit` characters to paint, its whole size and where to
/// read it whole (spec F9, memory). A 60 MB session never sits in memory as text.
public struct ExcerptText: Equatable, Sendable {
    public static let limit = 2_000

    public let excerpt: String
    public let byteCount: Int
    public let lineCount: Int
    public let location: TextLocation

    public var isTruncated: Bool { excerpt.utf8.count < byteCount }

    public init(excerpt: String, byteCount: Int, lineCount: Int, location: TextLocation) {
        self.excerpt = excerpt
        self.byteCount = byteCount
        self.lineCount = lineCount
        self.location = location
    }

    public static func make(full: String, location: TextLocation) -> ExcerptText {
        ExcerptText(
            excerpt: String(full.prefix(limit)), byteCount: full.utf8.count,
            lineCount: full.isEmpty ? 0 : full.split(separator: "\n", omittingEmptySubsequences: false).count,
            location: location)
    }
}
