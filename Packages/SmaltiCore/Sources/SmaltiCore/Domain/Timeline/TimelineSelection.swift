/// Which row is chosen and whether the choice follows the newest row as the session grows (spec F9).
public struct TimelineSelection: Equatable, Sendable {
    public enum Direction: Sendable {
        case up, down
    }

    public let selected: TimelineItemID?
    /// Chosen on the last row: new rows move the choice to the new last one.
    public let followsTail: Bool

    public init(selected: TimelineItemID? = nil, followsTail: Bool = false) {
        self.selected = selected
        self.followsTail = followsTail
    }

    public func moved(_ direction: Direction, in rows: [TimelineRow]) -> TimelineSelection {
        guard let index = index(in: rows) else { return TimelineSelection().updated(for: rows) }
        let next = direction == .up ? max(0, index - 1) : min(rows.count - 1, index + 1)
        return TimelineSelection(selected: rows[next].id, followsTail: next == rows.count - 1)
    }

    /// → expands the chosen tool; anything else stays as it is.
    public func expanding(in rows: [TimelineRow], expanded: Set<TimelineItemID>) -> Set<TimelineItemID> {
        guard let row = row(in: rows), row.kind == .tool else { return expanded }
        return expanded.union([row.id])
    }

    /// ← collapses the chosen tool; on a collapsed row inside a subagent, it climbs to the parent tool.
    public func collapsing(in rows: [TimelineRow], expanded: Set<TimelineItemID>)
        -> (TimelineSelection, Set<TimelineItemID>)
    {
        guard let row = row(in: rows) else { return (self, expanded) }
        if expanded.contains(row.id) { return (self, expanded.subtracting([row.id])) }
        guard let parent = row.parent else { return (self, expanded) }
        return (TimelineSelection(selected: parent), expanded)
    }

    /// The choice for new rows: the new last row when following the tail, else the same row or, if it is gone, the
    /// nearest earlier one that still exists.
    public func updated(for rows: [TimelineRow], previous: [TimelineRow] = []) -> TimelineSelection {
        guard !rows.isEmpty else { return TimelineSelection() }
        if followsTail || selected == nil { return TimelineSelection(selected: rows.last?.id, followsTail: true) }
        if index(in: rows) != nil { return self }
        let ids = Set(rows.map(\.id))
        let earlier = previous.prefix { $0.id != selected }.reversed().first { ids.contains($0.id) }
        return TimelineSelection(selected: earlier?.id ?? rows.first?.id)
    }

    private func index(in rows: [TimelineRow]) -> Int? {
        rows.firstIndex { $0.id == selected }
    }

    private func row(in rows: [TimelineRow]) -> TimelineRow? {
        index(in: rows).map { rows[$0] }
    }
}
