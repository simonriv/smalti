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
    public static let chips = [
        Chip(title: "Todas", harness: nil), Chip(title: "Claude Code", harness: .claude),
        Chip(title: "Codex", harness: .codex), Chip(title: "Antigravity", harness: .antigravity),
        Chip(title: "OpenCode", harness: .opencode),
    ]

    public var text = ""
    public private(set) var chipIndex = 0
    public var listing = SessionListing(sessions: [], failures: [:]) {
        didSet { selectedIndex = min(selectedIndex, max(listing.sessions.count - 1, 0)) }
    }
    public private(set) var selectedIndex = 0

    public init() {}

    public var query: SessionQuery { SessionQuery(harness: Self.chips[chipIndex].harness, text: text) }

    public var selected: HarnessSession? {
        listing.sessions.indices.contains(selectedIndex) ? listing.sessions[selectedIndex] : nil
    }

    public mutating func selectChip(_ index: Int) {
        guard Self.chips.indices.contains(index) else { return }
        chipIndex = index
        selectedIndex = 0
    }

    public mutating func nextChip() { selectChip((chipIndex + 1) % Self.chips.count) }

    public mutating func previousChip() { selectChip((chipIndex + Self.chips.count - 1) % Self.chips.count) }

    public mutating func moveSelection(by offset: Int) {
        guard !listing.sessions.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), listing.sessions.count - 1)
    }

    public mutating func select(id: String) {
        if let index = listing.sessions.firstIndex(where: { $0.id == id }) { selectedIndex = index }
    }

    public func rows(now: Date, calendar: Calendar) -> [SessionSearchRow] {
        listing.sessions.map { session in
            let detail = [session.harness.displayName, session.project, session.detail].compactMap { $0 }
            return SessionSearchRow(
                id: session.id, harness: session.harness, title: session.title.isEmpty ? session.project : session.title,
                day: RelativeDay.label(session.updatedAt, now: now, calendar: calendar),
                detail: detail.joined(separator: " · "))
        }
    }

    /// What shows instead of rows when there are none.
    public var emptyText: String? {
        guard listing.sessions.isEmpty else { return nil }
        return text.isEmpty ? "No hay sesiones de agentes en este Mac" : "Sin sesiones que coincidan"
    }

    public var failureMessages: [String] {
        listing.failures.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value.message)
    }
}

/// "hoy", "ayer", the weekday within the week, else "18 nov" (the board's "ayer", "jue").
public enum RelativeDay {
    static let weekdays = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]
    static let months = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

    public static func label(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? 0
        switch days {
        case ...0: return "hoy"
        case 1: return "ayer"
        case 2...6: return weekdays[(calendar.component(.weekday, from: date) - 1) % 7]
        default:
            let parts = calendar.dateComponents([.day, .month], from: date)
            return "\(parts.day ?? 1) \(months[((parts.month ?? 1) - 1) % 12])"
        }
    }
}
