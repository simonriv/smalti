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
            // The group's leader may have ended while the group stays in front: any member names the terminal.
            let member = byPID[group] ?? records.first { $0.processGroup == group && $0.terminal != nil }
            if let terminal = member?.terminal { panes[terminal] = pane }
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

    /// The pane's own process, the one ⌘W closes: the shell (or the pane's command), child of root's `login` on the
    /// same terminal, which is the top of the pane (its own parent, Smalti, is in no pane). Something launchd adopted
    /// or root's `sudo` started inside the pane is not it. An unknown parent counts as the top: protecting by mistake
    /// is the safe side.
    public func isPaneRoot(_ pid: Int32) -> Bool {
        guard let record = records[pid], record.isOwn, let pane = pane(of: pid) else { return false }
        guard let parent = records[record.parent] else { return true }
        let isTopOfPane = self.pane(of: parent.parent) != pane
        return !parent.isOwn && parent.terminal == record.terminal && isTopOfPane
    }
}
