/// A project's pane count and layout, as the confirmation compares them.
public struct ProjectArrangement: Equatable, Sendable {
    public let paneCount: Int
    public let layout: String

    public init(_ paneCount: Int, _ layout: String) {
        self.paneCount = paneCount
        self.layout = layout
    }
}

public struct ProjectArrangementChange: Equatable, Sendable {
    public let before: ProjectArrangement
    public let after: ProjectArrangement

    public init(before: ProjectArrangement, after: ProjectArrangement) {
        self.before = before
        self.after = after
    }
}

/// One command of the confirmation and whether it is new since the approval.
public struct ProjectCommandLine: Equatable, Sendable {
    public enum Kind: String, Sendable { case same, added, removed }

    public let command: PlannedCommand
    public let kind: Kind
}

/// What a project's file runs now against what the user approved (F8.5): the current commands in their order, each
/// unchanged or added (counted as a multiset, so a second `npm test` is new), then the approved ones that are gone.
public struct ProjectChanges: Equatable, Sendable {
    public let lines: [ProjectCommandLine]
    public let arrangement: ProjectArrangementChange?
    public let isFirstTime: Bool

    public init(approved: ProjectApproval?, current: [PlannedCommand], paneCount: Int, layout: String) {
        isFirstTime = approved == nil
        var remaining = approved?.commands ?? current
        var lines: [ProjectCommandLine] = []
        for command in current {
            if let index = remaining.firstIndex(of: command) {
                remaining.remove(at: index)
                lines.append(ProjectCommandLine(command: command, kind: .same))
            } else {
                lines.append(ProjectCommandLine(command: command, kind: .added))
            }
        }
        self.lines = lines + remaining.map { ProjectCommandLine(command: $0, kind: .removed) }
        let now = ProjectArrangement(paneCount, layout)
        arrangement = approved.flatMap { approval in
            let before = ProjectArrangement(approval.paneCount, approval.layout)
            return before == now ? nil : ProjectArrangementChange(before: before, after: now)
        }
    }

    /// The file changed, but neither its commands nor its arrangement did (ratios, order of keys…).
    public var hasSameCommands: Bool {
        !isFirstTime && arrangement == nil && lines.allSatisfy { $0.kind == .same }
    }
}
