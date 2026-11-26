import Foundation

/// Panes whose agent waits or failed, the longest waiting first; ties keep workspace and pane order.
public enum AttentionQueue {
    public static func panes(in set: WorkspaceSet) -> [PaneID] {
        panes(set.workspaces.flatMap(\.panes))
    }

    /// F4.5 ⌘J: every window's panes, longest waiting first; ties go by window, then position.
    public static func panes(in windows: WindowSet) -> [PaneID] {
        panes(windows.allPanes)
    }

    private static func panes(_ panes: [Pane]) -> [PaneID] {
        let waiting = panes.enumerated().compactMap { position, pane in
            pane.agent?.state.since.map { (since: $0, position: position, id: pane.id) }
        }
        return waiting.sorted { ($0.since, $0.position) < ($1.since, $1.position) }.map(\.id)
    }
}

/// The counters of the workspace strip.
public struct AgentCounts: Equatable, Sendable {
    public let working: Int
    public let waiting: Int
    public let failed: Int

    public init(working: Int, waiting: Int, failed: Int) {
        self.working = working
        self.waiting = waiting
        self.failed = failed
    }

    public static func of(_ set: WorkspaceSet) -> AgentCounts {
        let kinds = set.workspaces.flatMap(\.panes).compactMap(\.agent?.state.kind)
        return AgentCounts(
            working: kinds.count { $0 == .working }, waiting: kinds.count { $0 == .waiting },
            failed: kinds.count { $0 == .failed })
    }
}

/// A macOS notification about one pane: "rizaria/web" and what happened.
public struct AttentionNotice: Equatable, Sendable {
    public let pane: PaneID
    public let title: String
    public let body: String

    public init(pane: PaneID, title: String, body: String) {
        self.pane = pane
        self.title = title
        self.body = body
    }

    public static func make(
        _ reason: AttentionReason, at place: (workspace: String, directory: WorkingDirectory, pane: PaneID),
        texts: StatusTexts
    ) -> AttentionNotice {
        AttentionNotice(
            pane: place.pane, title: "\(place.workspace)/\(place.directory.lastComponent)",
            body: body(for: reason, texts: texts))
    }

    private static func body(for reason: AttentionReason, texts: StatusTexts) -> String {
        switch reason {
        case .permission(let summary):
            summary.isEmpty ? texts.asksPermission : texts.asksPermissionFor(["summary": summary])
        case .attention(let message): message
        case .turnFinished: texts.turnFinished
        case .failure(let message): texts.failure(["message": message])
        case .approval(let command, let environment):
            texts.approval(["command": command, "environment": texts.guards.environments[environment] ?? ""])
        }
    }
}

/// When an agent's event becomes a macOS notification (decided by Simón): a finished turn only if the user is not
/// looking at that pane; a permission request, a notification or a failure always.
public enum AttentionPolicy {
    public static func shouldNotify(_ reason: AttentionReason, paneIsVisible: Bool) -> Bool {
        reason == .turnFinished ? !paneIsVisible : true
    }
}

/// "2m", "1h 12m": how long a pane has been waiting, for its header.
public enum ElapsedText {
    public static func short(since: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(since)) / 60)
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
