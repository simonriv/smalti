import Foundation

/// A workspace already open somewhere, as the projects see it: its project and where it is.
public struct OpenProjectWorkspace: Equatable, Sendable {
    public let id: WorkspaceID
    public let project: String?
    public let isInThisWindow: Bool
    /// Its position in its window, counting from 1.
    public let number: Int

    public init(id: WorkspaceID, project: String?, isInThisWindow: Bool, number: Int) {
        self.id = id
        self.project = project
        self.isInThisWindow = isInThisWindow
        self.number = number
    }
}

/// A project's file read once and ready to open: what the confirmation shows is what opens and what is approved.
public struct PreparedProject: Equatable, Sendable {
    public let root: String
    public let name: LayoutName
    /// The workspace to open, marked as the project's.
    public let snapshot: WorkspaceSnapshot
    public let fingerprint: String
    public let commands: [PlannedCommand]

    public init(
        root: String, name: LayoutName, snapshot: WorkspaceSnapshot, fingerprint: String, commands: [PlannedCommand]
    ) {
        self.root = root
        self.name = name
        self.snapshot = snapshot
        self.fingerprint = fingerprint
        self.commands = commands
    }
}

public struct ProjectConfirmation: Equatable, Sendable {
    public let prepared: PreparedProject
    public let changes: ProjectChanges
    /// What Smalti degrades in the file (an unknown harness or layout): the card says it (final review).
    public let warnings: [SharedLayoutWarning]
    /// When the user approved an earlier version of the file; `nil` the first time.
    public let approvedAt: Date?

    public init(
        prepared: PreparedProject, changes: ProjectChanges, approvedAt: Date?, warnings: [SharedLayoutWarning] = []
    ) {
        self.prepared = prepared
        self.changes = changes
        self.warnings = warnings
        self.approvedAt = approvedAt
    }
}

public enum ProjectStep: Equatable, Sendable {
    case jump(WorkspaceID)
    case open(PreparedProject)
    case confirm(ProjectConfirmation)
}

/// Opens a project (F8.5): jumps to its workspace when it is open; otherwise reads its file and opens it, after a
/// confirmation when it runs commands the user has not approved in this exact file. `prepare` never runs anything;
/// the app opens the prepared workspace and then calls `opened`.
@MainActor
public struct OpenProject {
    private let files: any ProjectFiles
    private let records: any ProjectRecords
    private let harnesses: HarnessRegistry
    private let home: String
    private let clock: @Sendable () -> Date

    public init(
        files: any ProjectFiles, records: any ProjectRecords, harnesses: HarnessRegistry, home: String,
        clock: @escaping @Sendable () -> Date
    ) {
        self.files = files
        self.records = records
        self.harnesses = harnesses
        self.home = home
        self.clock = clock
    }

    public func prepare(root: String, open: [OpenProjectWorkspace]) throws(ProjectFileError) -> ProjectStep {
        let root = files.realPath(root)
        if let workspace = open.first(where: { $0.project == root }) { return .jump(workspace.id) }
        let file = try files.layout(at: root)
        let validated: ValidatedLayout
        do { validated = try file.layout.validatedAsProject() } catch { throw .invalid(error) }
        try checkLinksStayInside(validated.layout, root: root)
        try checkFoldersExist(validated.layout, root: root)
        let prepared = Self.prepared(
            validated, root: root, fingerprint: file.fingerprint, home: home, harnesses: harnesses)
        let approval = RecentProjects(records: records.all()).record(at: root)?.approval
        // Approved means these bytes and these commands as shown: a newer Smalti may run more from the same file.
        let isApproved = approval?.fingerprint == file.fingerprint && approval?.commands == prepared.commands
        let runsNothing = prepared.commands.isEmpty && validated.warnings.isEmpty
        if isApproved || runsNothing { return .open(prepared) }
        let changes = ProjectChanges(
            approved: approval, current: prepared.commands, paneCount: prepared.snapshot.panes.count,
            layout: prepared.snapshot.layout)
        return .confirm(
            ProjectConfirmation(
                prepared: prepared, changes: changes, approvedAt: approval?.approvedAt, warnings: validated.warnings))
    }

    /// What approving a confirmation does now: the project may have been opened meanwhile from another window, and
    /// then it jumps there instead of running its commands a second time (review 2).
    public func approved(_ prepared: PreparedProject, open: [OpenProjectWorkspace]) -> ProjectStep {
        open.first { $0.project == prepared.root }.map { .jump($0.id) } ?? .open(prepared)
    }

    /// The prepared project opened: it goes first among the recents, with this file approved.
    public func opened(_ prepared: PreparedProject) throws(ProjectFileError) {
        let now = clock()
        let approval = ProjectApproval(
            fingerprint: prepared.fingerprint, approvedAt: now, commands: prepared.commands,
            paneCount: prepared.snapshot.panes.count, layout: prepared.snapshot.layout)
        try record(root: prepared.root, name: prepared.name.rawValue, approval: approval)
    }

    /// The user jumped to the project's open workspace: it goes first among the recents.
    public func jumped(to root: String) throws(ProjectFileError) {
        let root = files.realPath(root)
        let recents = RecentProjects(records: records.all())
        let name = recents.record(at: root)?.name ?? URL(filePath: root).lastPathComponent
        try record(root: root, name: name, approval: nil)
    }

    /// A folder or editor file that is a link (or under one) leaving the repo would run or open outside it while the
    /// confirmation shows a path inside (review 1).
    private func checkLinksStayInside(_ layout: SharedLayout, root: String) throws(ProjectFileError) {
        for (index, pane) in layout.panes.enumerated() {
            let directory = Self.joined(root, pane.directory)
            var paths = [(pane.directory, directory)]
            if let editor = pane.editor { paths.append((editor.file, Self.joined(directory, editor.file))) }
            for (written, path) in paths where !Self.isInside(files.realPath(path), root: root) {
                throw .invalid(.outsideProject(pane: index + 1, path: written))
            }
        }
    }

    /// A command, agent or editor runs only in its own folder: one that does not exist is an error, never the root.
    private func checkFoldersExist(_ layout: SharedLayout, root: String) throws(ProjectFileError) {
        for (index, pane) in layout.panes.enumerated()
        where pane.command != nil || pane.harness != nil
            || pane.editor != nil
        {
            guard files.folderExists(Self.joined(root, pane.directory)) else {
                throw .missingFolder(pane: index + 1, path: pane.directory)
            }
        }
    }

    private static func joined(_ base: String, _ relative: String) -> String {
        relative == "." ? base : base + "/" + relative
    }

    private static func isInside(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    private func record(root: String, name: String, approval: ProjectApproval?) throws(ProjectFileError) {
        let recents = RecentProjects(records: records.all()).opening(
            root: root, name: name, at: clock(), approval: approval)
        try records.replace(with: recents.ordered)
    }

    private static func prepared(
        _ validated: ValidatedLayout, root: String, fingerprint: String, home: String, harnesses: HarnessRegistry
    ) -> PreparedProject {
        let opened = validated.layout.workspaceSnapshot(root: root, home: home)
        let snapshot = WorkspaceSnapshot(
            name: validated.name.rawValue, rootDirectory: root, layout: opened.layout, tree: opened.tree,
            focusedIndex: opened.focusedIndex, panes: opened.panes, project: root)
        return PreparedProject(
            root: root, name: validated.name, snapshot: snapshot, fingerprint: fingerprint,
            commands: PlannedCommands.of(validated.layout, root: root, home: home, harnesses: harnesses))
    }
}
