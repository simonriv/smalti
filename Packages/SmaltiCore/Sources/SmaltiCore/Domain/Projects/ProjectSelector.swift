import Foundation

/// One project of the ⌘O selector, with its words ready.
public struct ProjectSelectorRow: Equatable, Sendable {
    public let root: String
    public let name: String
    /// The root with `~`.
    public let path: String
    /// "abierto · workspace 1", "hace 2 h", "en este panel" or nothing.
    public let detail: String
    public let isOpen: Bool
}

/// The ⌘O selector (F8.5): the projects filtered by what the user typed and which one is chosen. It opens on the
/// first project that is not the active workspace's, so ⌘O ↩ goes back to the previous project; ⌘O and ↑↓ wrap.
public struct ProjectSelector: Equatable, Sendable {
    public struct Context: Equatable, Sendable {
        let home: String
        let now: Date
        let texts: ProjectTexts
        let time: TimeTexts

        public init(home: String, now: Date, texts: ProjectTexts, time: TimeTexts) {
            self.home = home
            self.now = now
            self.texts = texts
            self.time = time
        }
    }

    private let listings: [ProjectListing]
    private let context: Context
    private let query: String
    public let rows: [ProjectSelectorRow]
    public let selected: Int

    public init(listings: [ProjectListing], activeProject: String?, context: Context) {
        self.init(listings: listings, context: context, query: "", selected: 0)
        if let first = rows.firstIndex(where: { $0.root != activeProject }) {
            self = ProjectSelector(listings: listings, context: context, query: "", selected: first)
        }
    }

    private init(listings: [ProjectListing], context: Context, query: String, selected: Int) {
        self.listings = listings
        self.context = context
        self.query = query
        rows = Self.matching(listings, query: query).map { Self.row($0, context: context) }
        self.selected = rows.indices.contains(selected) ? selected : 0
    }

    public var selectedRoot: String? { rows.indices.contains(selected) ? rows[selected].root : nil }

    /// What the list says when it has no rows.
    public var emptyText: String {
        query.isEmpty ? context.texts.empty : context.texts.noMatch(["query": query])
    }

    public func moving(by step: Int) -> ProjectSelector {
        guard !rows.isEmpty else { return self }
        let next = ((selected + step) % rows.count + rows.count) % rows.count
        return ProjectSelector(listings: listings, context: context, query: query, selected: next)
    }

    public func selecting(_ index: Int) -> ProjectSelector {
        guard rows.indices.contains(index) else { return self }
        return ProjectSelector(listings: listings, context: context, query: query, selected: index)
    }

    public func filtering(_ text: String) -> ProjectSelector {
        ProjectSelector(listings: listings, context: context, query: text, selected: 0)
    }

    private static func matching(_ listings: [ProjectListing], query: String) -> [ProjectListing] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return listings }
        // The name matches loosely (letters in order); the path only as written, or every path would match.
        return listings.filter {
            fuzzyScore(trimmed, in: $0.name) != nil || $0.root.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private static func row(_ listing: ProjectListing, context: Context) -> ProjectSelectorRow {
        ProjectSelectorRow(
            root: listing.root, name: listing.name, path: ProjectPath.display(listing.root, home: context.home),
            detail: detail(listing, context: context), isOpen: listing.openIn != nil)
    }

    private static func detail(_ listing: ProjectListing, context: Context) -> String {
        if let open = listing.openIn {
            return open.isInThisWindow
                ? context.texts.openBadge(["number": String(open.number)]) : context.texts.openInAnotherWindow
        }
        if let opened = listing.lastOpened {
            return ElapsedPhrase.text(since: opened, now: context.now, texts: context.time)
        }
        return listing.isInFocusedPane ? context.texts.inThisPane : ""
    }
}
