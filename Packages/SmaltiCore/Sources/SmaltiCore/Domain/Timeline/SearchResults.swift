/// A line an adapter found for a query: the session, the entry and the whole text it searched.
public struct TranscriptHit: Equatable, Sendable {
    public let session: HarnessSession
    public let entry: TranscriptEntry
    public let text: String

    public init(session: HarnessSession, entry: TranscriptEntry, text: String) {
        self.session = session
        self.entry = entry
        self.text = text
    }
}

public struct SearchMatch: Equatable, Sendable {
    public let hit: TranscriptHit
    public let range: Range<String.Index>
}

public struct SearchGroup: Equatable, Sendable {
    public let session: HarnessSession
    public fileprivate(set) var matches: [SearchMatch]
}

/// The search's results so far: only hits whose visible text holds the query, grouped by session in the order they
/// came (newest session first, as the adapters search), at most `cap`.
public struct SearchResults: Equatable, Sendable {
    public static let cap = 200

    public private(set) var groups: [SearchGroup] = []
    public private(set) var isCapped = false

    public init() {}

    public var matchCount: Int { groups.reduce(0) { $0 + $1.matches.count } }

    public func adding(_ hit: TranscriptHit, query: TimelineQuery) -> SearchResults {
        guard let range = TimelineMatch.find(query, in: hit.text) else { return self }
        var results = self
        guard matchCount < Self.cap else {
            results.isCapped = true
            return results
        }
        let match = SearchMatch(hit: hit, range: range)
        if let index = results.groups.firstIndex(where: {
            $0.session.harness == hit.session.harness && $0.session.id == hit.session.id
        }) {
            results.groups[index].matches.append(match)
        } else {
            results.groups.append(SearchGroup(session: hit.session, matches: [match]))
        }
        return results
    }
}
