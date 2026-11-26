import Foundation

/// One row of the session search, as `Reanudar.dc.html` draws it: title and day, then "Harness · proyecto · detalle".
public struct SessionSearchRow: Equatable, Sendable {
    public let id: String
    public let harness: HarnessID
    public let title: String
    public let day: String
    public let detail: String
}

/// The session search's state (spec F6): the harness chip, the typed text, the listing and the selection. The view
/// draws it; the keys change it.
public struct SessionSearchState: Equatable, Sendable {
    public struct Chip: Equatable, Sendable {
        public let title: String
        public let harness: HarnessID?
    }

    /// The board's chips, without Gemini (spec F6).
    public static func chips(_ texts: SessionTexts) -> [Chip] {
        chipHarnesses.map { Chip(title: $0?.displayName ?? texts.allHarnesses, harness: $0) }
    }

    /// The chips' filters, in order; nil is every harness.
    static let chipHarnesses: [HarnessID?] = [nil, .claude, .codex, .antigravity, .opencode]

    /// New text selects the top match again.
    public var text = "" {
        didSet { if text != oldValue { selectedIndex = 0 } }
    }
    public private(set) var chipIndex = 0
    /// A late listing (a slow harness) keeps the selected session, wherever it now sits; a session no longer listed
    /// gives the selection back to the top.
    public var listing = SessionListing(sessions: [], failures: [:]) {
        didSet {
            let previous = oldValue.sessions.indices.contains(selectedIndex) ? oldValue.sessions[selectedIndex] : nil
            selectedIndex =
                previous.flatMap { kept in
                    listing.sessions.firstIndex { $0.id == kept.id && $0.harness == kept.harness }
                } ?? 0
        }
    }
    public private(set) var selectedIndex = 0

    public init() {}

    public var query: SessionQuery { SessionQuery(harness: Self.chipHarnesses[chipIndex], text: text) }

    public var selected: HarnessSession? {
        listing.sessions.indices.contains(selectedIndex) ? listing.sessions[selectedIndex] : nil
    }

    public mutating func selectChip(_ index: Int) {
        guard Self.chipHarnesses.indices.contains(index) else { return }
        chipIndex = index
        selectedIndex = 0
    }

    public mutating func nextChip() { selectChip((chipIndex + 1) % Self.chipHarnesses.count) }

    public mutating func previousChip() {
        selectChip((chipIndex + Self.chipHarnesses.count - 1) % Self.chipHarnesses.count)
    }

    public mutating func moveSelection(by offset: Int) {
        guard !listing.sessions.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), listing.sessions.count - 1)
    }

    public mutating func select(id: String) {
        if let index = listing.sessions.firstIndex(where: { $0.id == id }) { selectedIndex = index }
    }

    public func rows(now: Date, calendar: Calendar, texts: SessionTexts) -> [SessionSearchRow] {
        listing.sessions.map { session in
            let tokens = session.tokens.map {
                texts.tokens(["n": ResumeListing.grouped($0, separator: texts.thousandsSeparator)])
            }
            let detail = [session.harness.displayName, session.project, session.detail, tokens].compactMap { $0 }
            return SessionSearchRow(
                id: session.id, harness: session.harness,
                title: session.title.isEmpty ? session.project : session.title,
                day: RelativeDay.label(session.updatedAt, now: now, calendar: calendar, texts: texts),
                detail: detail.joined(separator: " · "))
        }
    }

    /// What shows instead of rows when there are none.
    public func emptyText(_ texts: SessionTexts) -> String? {
        guard listing.sessions.isEmpty else { return nil }
        return text.isEmpty ? texts.noSessions : texts.noMatches
    }

    public func failureMessages(_ texts: SessionTexts) -> [String] {
        listing.failures.sorted { $0.key.rawValue < $1.key.rawValue }.map { $0.value.message(texts) }
    }
}

/// "hoy", "ayer", the weekday within the week, else "18 nov" (the board's "ayer", "jue").
public enum RelativeDay {
    public static func label(_ date: Date, now: Date, calendar: Calendar, texts: SessionTexts) -> String {
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? 0
        switch days {
        case ...0: return texts.today
        case 1: return texts.yesterday
        case 2...6: return texts.weekdays[(calendar.component(.weekday, from: date) - 1) % 7]
        default:
            let parts = calendar.dateComponents([.day, .month], from: date)
            return texts.dayMonth([
                "day": String(parts.day ?? 1), "month": texts.months[((parts.month ?? 1) - 1) % 12],
            ])
        }
    }
}
