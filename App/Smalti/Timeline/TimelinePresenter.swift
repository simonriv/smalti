import Foundation
import SmaltiCore

/// Words the timeline's states for the view: times and sizes in the interface's language, the domain's texts and
/// the view's own key hints. Every transcript text reaches the view through `TimelineRows` (the text policy).
@MainActor
struct TimelinePresenter {
    let texts: TimelineTexts
    let policy: any TranscriptTextPolicy

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func time(_ date: Date) -> String { time.string(from: date) }
    static func day(_ date: Date) -> String { day.string(from: date) }

    func rows(_ session: ShowTimeline.TimelineSession, expanded: Set<TimelineItemID>) -> [TimelineRow] {
        TimelineRows.rows(
            session.timeline, harness: session.ref.harness, expanded: expanded, policy: policy, texts: texts,
            time: Self.time)
    }

    func info(_ session: ShowTimeline.TimelineSession, paneName: String, agentDot: StatusDotStyle)
        -> TimelineScreen.SessionInfo
    {
        let timeline = session.timeline
        var line = "\(session.ref.harness.displayName) · \(paneName)"
        if session.isUnidentified { line += " · \(texts.unidentifiedTag)" }
        var figures = "\(texts.turns(timeline.turnCount)) · \(texts.tools(timeline.toolCount))"
        if let start = timeline.startedAt { figures += " · " + texts.since(["time": Self.time(start)]) }
        let title = timeline.turns.lazy.compactMap(\.prompt).first.map { policy.shown($0.text.excerpt, as: .display) }
        return TimelineScreen.SessionInfo(
            dot: agentDot, line: line, title: title?.split(separator: "\n").first.map(String.init) ?? "",
            figures: figures)
    }

    func banner(_ session: ShowTimeline.TimelineSession, directory: String) -> String? {
        guard session.isUnidentified else { return nil }
        return texts.unidentified(["harness": session.ref.harness.displayName, "directory": directory])
    }

    func recent(_ sessions: [HarnessSession], live: Set<String>) -> [TimelineScreen.Recent] {
        sessions.map { session in
            TimelineScreen.Recent(
                title: policy.shown(session.title.isEmpty ? session.id : session.title, as: .display),
                meta: "\(session.harness.displayName) · \(Self.day(session.updatedAt))",
                isLive: live.contains(session.id))
        }
    }

    func searchItems(_ results: SearchResults, currentSession: String?, live: [String: String])
        -> [TimelineScreen.SearchItem]
    {
        results.groups.flatMap { group -> [TimelineScreen.SearchItem] in
            let session = group.session
            let place =
                session.id == currentSession
                ? texts.thisPane
                : live[session.id].map { texts.openIn(["pane": $0]) }
                    ?? texts.closed(["when": Self.day(session.updatedAt)])
            let header = TimelineScreen.SearchItem.group(
                title: policy.shown(session.title.isEmpty ? session.id : session.title, as: .searchSnippet),
                meta: "\(session.harness.displayName) · \(place)", count: group.matches.count)
            return [header] + group.matches.map { hit($0) }
        }
    }

    private func hit(_ match: SearchMatch) -> TimelineScreen.SearchItem {
        .hit(
            who: who(match.entry, harness: match.session.harness), time: match.entry.at.map(Self.time) ?? "",
            snippet: match.snippet, match: NSRange(match.range, in: match.snippet))
    }

    private func who(_ entry: TranscriptEntry, harness: HarnessID) -> String {
        switch entry.kind {
        case .prompt: texts.you
        case .reply: harness == .codex ? "Codex" : "Claude"
        case .toolCall(let call): call.name
        case .toolResult: texts.output
        case .image, .compaction, .subagentLink: ""
        }
    }

    func summary(_ search: SearchTranscripts) -> String {
        let results = search.results
        if search.isSearching { return texts.searching }
        if results.matchCount == 0 { return search.query.isEmpty ? "" : texts.noMatch(["query": search.query.raw]) }
        var summary = "\(texts.matches(results.matchCount)) \(texts.inSessions(results.groups.count))"
        if results.isCapped { summary += " · " + texts.capped(["count": String(SearchResults.cap)]) }
        return summary
    }

    // MARK: - Keys (view texts)

    static func sessionKeys() -> [(key: String, label: String)] {
        [
            ("↑↓", String(localized: "choose")), ("→ ←", String(localized: "expand")),
            ("⌘C", String(localized: "copy whole")), ("esc", String(localized: "close")),
        ]
    }

    static func searchKeys() -> [(key: String, label: String)] {
        [
            ("↑↓", String(localized: "choose")), ("↵", String(localized: "jump to turn")),
            ("⌘C", String(localized: "copy whole")), ("esc", String(localized: "back")),
        ]
    }

    static func emptyKeys() -> [(key: String, label: String)] {
        [
            ("↑↓", String(localized: "choose")), ("↵", String(localized: "open")),
            ("⌘F", String(localized: "search")), ("esc", String(localized: "close")),
        ]
    }
}

extension TimelineTexts: Bilingual {}
