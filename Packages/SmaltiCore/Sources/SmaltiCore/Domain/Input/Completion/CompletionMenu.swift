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
/// zsh keeps the line while the menu is open; every change of it refilters, and ↩ only ever inserts.
public struct CompletionMenu: Equatable, Sendable {
    private enum State: Equatable, Sendable {
        case closed
        case waiting(InputLine)
        case open(line: InputLine, items: [Suggestion])
    }

    private var state = State.closed
    public private(set) var visible: [Suggestion] = []
    public private(set) var selected = 0

    public init() {}

    public var isOpen: Bool {
        if case .open = state { return true }
        return false
    }

    public mutating func request(for line: InputLine) {
        state = .waiting(line)
    }

    public mutating func receive(_ items: [Suggestion], for line: InputLine) -> MenuEffect {
        guard state == .waiting(line) else { return .none }
        if items.isEmpty { return close(with: .fallback) }
        if items.count == 1 { return close(with: .insert(CompletionEngine.insertion(of: items[0], into: line))) }
        let common = Self.commonPrefix(of: items.map(\.name))
        guard common.count > line.currentWord.text.count else { return open(on: line, items: items) }
        // Literal text (insertValue), so the spaces are escaped here, as `insertion` does for names.
        let escaped = line.currentWord.isQuoted ? common : common.replacingOccurrences(of: " ", with: "\\ ")
        let extended = CompletionEngine.insertion(
            of: Suggestion(name: common, insertValue: escaped + "{cursor}"), into: line)
        _ = open(on: extended, items: items)
        return .insertThenShow(extended)
    }

    /// Generated items arrive after the fixed ones: they join without moving the selection.
    public mutating func addGenerated(_ generated: [Suggestion], for line: InputLine) -> MenuEffect {
        guard case .open(let current, let items) = state, !generated.isEmpty else { return .none }
        let keep = selected
        _ = open(on: current, items: items + generated)
        selected = min(keep, max(visible.count - 1, 0))
        return .show
    }

    public mutating func lineChanged(_ line: InputLine) -> MenuEffect {
        switch state {
        case .closed: return .none
        case .waiting: return close(with: .none)
        case .open(let current, let items):
            guard line != current else { return .none }
            return open(on: line, items: items)
        }
    }

    public mutating func press(_ key: MenuKey) -> MenuEffect {
        guard case .open(let line, _) = state, !visible.isEmpty else { return .none }
        switch key {
        case .up: selected = (selected - 1 + visible.count) % visible.count
        case .down: selected = (selected + 1) % visible.count
        case .tab, .enter: return close(with: .insert(CompletionEngine.insertion(of: visible[selected], into: line)))
        case .escape, .other: return close(with: .close)
        }
        return .show
    }

    private mutating func open(on line: InputLine, items: [Suggestion]) -> MenuEffect {
        visible = CompletionEngine.rank(items, prefix: line.currentWord.text, history: nil)
        guard !visible.isEmpty else { return close(with: .close) }
        state = .open(line: line, items: items)
        selected = min(selected, visible.count - 1)
        return .show
    }

    private mutating func close(with effect: MenuEffect) -> MenuEffect {
        state = .closed
        visible = []
        selected = 0
        return effect
    }

    private static func commonPrefix(of names: [String]) -> String {
        guard var prefix = names.first else { return "" }
        for name in names.dropFirst() {
            while !name.hasPrefix(prefix) { prefix.removeLast() }
        }
        return prefix
    }
}
