public enum MenuKey: Sendable {
    case up, down, tab, enter, escape, other
}

/// What the app does after the menu handles an event. `insertThenShow` writes the common prefix and keeps the
/// menu open on the new line.
public enum MenuEffect: Equatable, Sendable {
    case none
    case show
    case close
    case insert(InputLine)
    case insertThenShow(InputLine)
    case fallback
}

/// The Tab menu: closed, waiting for the items of one line, or open on a line with the items that match it.
///
/// zsh keeps the line while the menu is open. An edit inside the word refilters; one outside it (a space, a
/// change before the word) closes the menu. ↩ only ever inserts. When generators are still running, the menu
/// waits for them before deciding between falling back, inserting a single match or showing.
public struct CompletionMenu: Equatable, Sendable {
    private struct Open: Equatable, Sendable {
        var line: InputLine
        /// The line the items were requested for: late generated items must belong to it.
        let origin: InputLine
        var items: [Suggestion]
        var isGenerating: Bool
    }

    private enum State: Equatable, Sendable {
        case closed
        case waiting(InputLine)
        case open(Open)
    }

    private var state = State.closed
    public private(set) var visible: [Suggestion] = []
    public private(set) var selected = 0

    public init() {}

    /// True while the menu is shown on screen.
    public var isOpen: Bool {
        if case .open = state { return !visible.isEmpty }
        return false
    }

    public mutating func request(for line: InputLine) {
        state = .waiting(line)
    }

    /// The fixed items for the requested line. With `generating`, more items will follow in `addGenerated`, so
    /// nothing is inserted or abandoned yet.
    public mutating func receive(_ items: [Suggestion], for line: InputLine, generating: Bool = false) -> MenuEffect {
        guard state == .waiting(line) else { return .none }
        guard generating else { return settle(items, on: line, origin: line) }
        return open(Open(line: line, origin: line, items: items, isGenerating: true))
    }

    /// The generators' items for `origin`; called once, also when they found nothing.
    public mutating func addGenerated(_ generated: [Suggestion], for origin: InputLine) -> MenuEffect {
        guard case .open(var current) = state, current.origin == origin else { return .none }
        if current.isGenerating && visible.isEmpty {
            return settle(current.items + generated, on: current.line, origin: origin)
        }
        current.isGenerating = false
        guard !generated.isEmpty else {
            state = .open(current)
            return .none
        }
        current.items += generated
        return open(current)
    }

    public mutating func lineChanged(_ line: InputLine) -> MenuEffect {
        switch state {
        case .closed: return .none
        case .waiting: return close(with: .none)
        case .open(var current):
            guard line != current.line else { return .none }
            guard Self.isSameWord(current.line, line) else { return close(with: .close) }
            current.line = line
            return open(current)
        }
    }

    public mutating func press(_ key: MenuKey) -> MenuEffect {
        guard case .open(let current) = state, !visible.isEmpty else { return .none }
        switch key {
        case .up: selected = (selected - 1 + visible.count) % visible.count
        case .down: selected = (selected + 1) % visible.count
        case .tab, .enter:
            return close(with: .insert(CompletionEngine.insertion(of: visible[selected], into: current.line)))
        case .escape, .other: return close(with: .close)
        }
        return .show
    }

    /// With every item known: none falls back to the user's Tab, a single prefix match is inserted, a longer
    /// common prefix of what was typed is written first, and anything else is shown.
    private mutating func settle(_ items: [Suggestion], on line: InputLine, origin: InputLine) -> MenuEffect {
        let typed = line.wordBeforeCursor
        if items.isEmpty { return close(with: .fallback) }
        if items.count == 1, items[0].name.hasPrefix(typed) {
            return close(with: .insert(CompletionEngine.insertion(of: items[0], into: line)))
        }
        let common = Self.commonPrefix(of: items.map(\.name))
        guard common.count > typed.count, common.hasPrefix(typed) else {
            return open(Open(line: line, origin: origin, items: items, isGenerating: false))
        }
        let extended = CompletionEngine.insertion(ofPrefix: common, into: line)
        _ = open(Open(line: extended, origin: origin, items: items, isGenerating: false))
        return .insertThenShow(extended)
    }

    /// Shows `current`'s items that match its line, keeping the selected suggestion when it is still there.
    private mutating func open(_ current: Open) -> MenuEffect {
        let previous = visible.indices.contains(selected) ? visible[selected] : nil
        visible = CompletionEngine.rank(current.items, prefix: current.line.wordBeforeCursor, history: nil)
        guard !visible.isEmpty || current.isGenerating else { return close(with: .close) }
        state = .open(current)
        selected = previous.flatMap { visible.firstIndex(of: $0) } ?? 0
        return visible.isEmpty ? .none : .show
    }

    private mutating func close(with effect: MenuEffect) -> MenuEffect {
        state = .closed
        visible = []
        selected = 0
        return effect
    }

    /// Both lines edit the same word: it starts at the same place and nothing before it changed.
    private static func isSameWord(_ old: InputLine, _ new: InputLine) -> Bool {
        let start = old.currentWord.range.lowerBound
        guard new.currentWord.range.lowerBound == start || new.wordBeforeCursor.isEmpty && new.cursor == start
        else { return false }
        return old.text.unicodeScalars.prefix(start).elementsEqual(new.text.unicodeScalars.prefix(start))
    }

    private static func commonPrefix(of names: [String]) -> String {
        guard var prefix = names.first else { return "" }
        for name in names.dropFirst() {
            while !name.hasPrefix(prefix) { prefix.removeLast() }
        }
        return prefix
    }
}
