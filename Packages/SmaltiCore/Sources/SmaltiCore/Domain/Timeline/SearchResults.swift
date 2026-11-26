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

/// A confirmed match: where it is and the policy's snippet around it, never the whole text (a search may keep 200).
public struct SearchMatch: Equatable, Sendable {
    public let session: HarnessSession
    public let entry: TranscriptEntry
    public let snippet: String
    public let range: Range<String.Index>
}

public struct SearchGroup: Equatable, Sendable {
    public let session: HarnessSession
    public fileprivate(set) var matches: [SearchMatch]
}

/// The search's results so far: only hits whose shown text holds the query, grouped by session, newest session
/// first, at most `cap`.
public struct SearchResults: Equatable, Sendable {
    public static let cap = 200
    /// Characters of a match's snippet.
    public static let snippetWidth = 120

    public private(set) var groups: [SearchGroup] = []
    public private(set) var isCapped = false

    public init() {}

    public var matchCount: Int { groups.reduce(0) { $0 + $1.matches.count } }

    /// Confirms a hit on the text the policy shows for search (spec F9, section 6) and cuts its snippet; nil when it
    /// does not hold the query. Runs off the main actor: it reads whole outputs.
    public static func confirm(_ hit: TranscriptHit, query: TimelineQuery, policy: any TranscriptTextPolicy)
        -> SearchMatch?
    {
        let shown = policy.shown(hit.text, as: .searchSnippet)
        guard let range = TimelineMatch.find(query, in: shown) else { return nil }
        let (snippet, inSnippet) = TimelineMatch.snippet(shown, around: range, width: snippetWidth)
        return SearchMatch(session: hit.session, entry: hit.entry, snippet: snippet, range: inSnippet)
    }

    public func adding(_ match: SearchMatch) -> SearchResults {
        var results = self
        guard matchCount < Self.cap else {
            results.isCapped = true
            return results
        }
        let session = match.session
        if let index = results.groups.firstIndex(where: {
            $0.session.harness == session.harness && $0.session.id == session.id
        }) {
            results.groups[index].matches.append(match)
        } else {
            let position =
                results.groups.firstIndex { $0.session.updatedAt < session.updatedAt } ?? results.groups.count
            results.groups.insert(SearchGroup(session: session, matches: [match]), at: position)
        }
        return results
    }
}
