import Foundation

/// One row's worth of facts: the transcript's activity joined with the live process and the Smalti pane.
public struct ObservedSession: Equatable, Sendable {
    public let id: String
    public let label: String
    public let state: AgentStateKind
    public let pane: PaneID?
    public let pid: Int32?
    public let startedAt: Date?
    public let activity: SessionActivity

    /// A row is live while its process runs or its pane still holds an active agent.
    public var isLive: Bool { pid != nil || (pane != nil && state != .stopped) }

    /// `status` values of `sessions/<pid>.json`; anything else counts as working and is reported once.
    private static let statusStates: [String: AgentStateKind] = [
        "busy": .working, "idle": .waiting, "waiting": .waiting,
    ]

    public static func merge(_ snapshot: ObservatorySnapshot) -> [ObservedSession] {
        let activities = Dictionary(snapshot.activity.sessions.map { ($0.sessionID, $0) }, uniquingKeysWith: { $1 })
        let running = Dictionary(snapshot.running.map { ($0.sessionID, $0) }, uniquingKeysWith: { $1 })
        let panes = Dictionary(snapshot.panes.map { ($0.session.sessionID, $0) }, uniquingKeysWith: { $1 })
        let ids = Set(activities.keys).union(running.keys).union(panes.keys)
        return ids.map { id in
            let process = running[id]
            let pane = panes[id]
            let activity = activities[id] ?? SessionActivity(sessionID: id)
            return ObservedSession(
                id: id,
                label: pane?.label ?? label(cwd: activity.cwd ?? process?.cwd ?? "", home: snapshot.home),
                state: pane?.session.state.kind ?? process.map { statusStates[$0.status] ?? .working } ?? .stopped,
                pane: pane?.pane, pid: process?.pid,
                startedAt: process?.startedAt ?? pane?.session.startedAt ?? activity.firstActivity,
                activity: activity)
        }
    }

    public static func unknownStatuses(in running: [RunningAgent]) -> Set<String> {
        Set(running.map(\.status).filter { statusStates[$0] == nil })
    }

    /// The last two folders (`solen/api`); just one right under home (`termotty`), and `~` for home itself.
    static func label(cwd: String, home: String) -> String {
        let trimmedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        if cwd == trimmedHome { return "~" }
        let parts = cwd.split(separator: "/").map(String.init)
        let parent = "/" + parts.dropLast().joined(separator: "/")
        if parent == trimmedHome || parts.count < 2 { return parts.last ?? cwd }
        return parts.suffix(2).joined(separator: "/")
    }
}
