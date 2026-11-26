/// Which pane each process came from. A pane's terminal is the one its foreground group runs on (even when that
/// group is led by root's `login` and has no readable name); a process belongs to a pane when it runs on that
/// terminal or one of its ancestors does, so what called `setsid` still counts. What re-parented to launchd has no
/// pane: nothing reliable says where it came from (spec F8, "Proceso ↔ panel").
public struct PaneAttribution: Sendable {
    private let records: [Int32: ProcessRecord]
    private let panesByTerminal: [Int32: PaneID]

    public init(records: [ProcessRecord], foregroundGroups: [PaneID: Int32]) {
        let byPID = Dictionary(records.map { ($0.pid, $0) }) { first, _ in first }
        self.records = byPID
        var panes: [Int32: PaneID] = [:]
        for (pane, group) in foregroundGroups {
            if let terminal = byPID[group]?.terminal { panes[terminal] = pane }
        }
        panesByTerminal = panes
    }

    public func pane(of pid: Int32) -> PaneID? {
        var visited: Set<Int32> = []
        var current = records[pid]
        while let record = current, visited.insert(record.pid).inserted {
            if let terminal = record.terminal, let pane = panesByTerminal[terminal] { return pane }
            current = records[record.parent]
        }
        return nil
    }

    /// The pane's own process, the one ⌘W closes: the shell (or the pane's command), whose parent is root's `login`.
    public func isPaneRoot(_ pid: Int32) -> Bool {
        guard let record = records[pid], record.isOwn, pane(of: pid) != nil else { return false }
        guard let parent = records[record.parent] else { return true }
        return !parent.isOwn || pane(of: parent.pid) == nil
    }
}
