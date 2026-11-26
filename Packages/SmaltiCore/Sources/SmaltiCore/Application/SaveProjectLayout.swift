import Foundation

public enum ProjectSaveError: Error, Equatable, Sendable {
    case layout(SharedLayoutError)
    case file(ProjectFileError)
}

/// What "Guardar layout del proyecto" will write, before writing it.
public struct PendingProjectSave: Equatable, Sendable {
    public let root: String
    public let name: LayoutName
    public let layout: SharedLayout
    /// What the file will run, for the replace confirmation.
    public let commands: [PlannedCommand]

    public init(root: String, name: LayoutName, layout: SharedLayout, commands: [PlannedCommand]) {
        self.root = root
        self.name = name
        self.layout = layout
        self.commands = commands
    }
}

extension ProjectSaveError {
    /// The reason after "No se pudo guardar el layout del proyecto: ".
    public func message(_ texts: ProjectTexts, layout: SharedLayoutErrorTexts) -> String {
        switch self {
        case .layout(let error): error.message(layout)
        case .file(let error): error.message(texts, layout: layout)
        }
    }
}

public enum ProjectSaveStep: Equatable, Sendable {
    case write(PendingProjectSave)
    /// The repo already has a file: replacing it asks first.
    case confirmReplace(PendingProjectSave)
}

/// Writes `.smalti/layout.json` from the active workspace (F8.5). The repo is the workspace's project; otherwise the
/// project discovered from the focused pane; otherwise the nearest folder with `.git`; otherwise the pane's folder.
/// What Smalti writes is approved as written.
@MainActor
public struct SaveProjectLayout {
    private let files: any ProjectFiles
    private let records: any ProjectRecords
    private let harnesses: HarnessRegistry
    private let home: String
    private let clock: @Sendable () -> Date

    public init(
        files: any ProjectFiles, records: any ProjectRecords, harnesses: HarnessRegistry,
        home: String, clock: @escaping @Sendable () -> Date
    ) {
        self.files = files
        self.records = records
        self.harnesses = harnesses
        self.home = home
        self.clock = clock
    }

    /// The repo the active workspace would be saved to.
    public func root(of workspace: Workspace, focusedDirectory: String) -> String {
        if let project = workspace.project { return project }
        let directory = files.realPath(focusedDirectory)
        let discovery = ProjectDiscovery(files: files, home: home)
        return discovery.root(containing: directory) ?? discovery.nearestRepository(from: directory) ?? directory
    }

    public func prepare(_ workspace: Workspace, focusedDirectory: String) throws(ProjectSaveError) -> ProjectSaveStep {
        let root = root(of: workspace, focusedDirectory: focusedDirectory)
        let exists = files.hasLayout(in: root)
        let name = existingName(at: root, exists: exists) ?? Self.folderName(root)
        let layout: SharedLayout
        do {
            layout = try SharedLayout(
                exportingProject: resolved(WorkspaceSnapshot(workspace, scrollbackLines: [:])), named: name,
                root: root, home: home)
        } catch { throw .layout(error) }
        let pending = PendingProjectSave(
            root: root, name: name, layout: layout,
            commands: PlannedCommands.of(layout, root: root, home: home, harnesses: harnesses))
        return exists ? .confirmReplace(pending) : .write(pending)
    }

    /// Writes the file and approves it: Smalti wrote what the user sees in their workspace.
    public func write(_ pending: PendingProjectSave) throws(ProjectSaveError) -> LayoutName {
        let fingerprint: String
        do { fingerprint = try files.write(pending.layout, to: pending.root) } catch { throw .file(error) }
        let snapshot = pending.layout.workspaceSnapshot(root: pending.root, home: home)
        let now = clock()
        let approval = ProjectApproval(
            fingerprint: fingerprint, approvedAt: now, commands: pending.commands, paneCount: snapshot.panes.count,
            layout: snapshot.layout)
        let recents = RecentProjects(records: records.all()).opening(
            root: pending.root, name: pending.layout.name, at: now, approval: approval)
        do { try records.replace(with: recents.ordered) } catch { throw .file(error) }
        return pending.name
    }

    /// The panes' folders and editor files as real paths, so a pane reached through a link (`/tmp` is
    /// `/private/tmp`) is inside the real root (review 1).
    private func resolved(_ snapshot: WorkspaceSnapshot) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            name: snapshot.name, rootDirectory: snapshot.rootDirectory, layout: snapshot.layout, tree: snapshot.tree,
            focusedIndex: snapshot.focusedIndex,
            panes: snapshot.panes.map { pane in
                PaneSnapshot(
                    id: pane.id, workingDirectory: files.realPath(pane.workingDirectory), title: pane.title,
                    processName: pane.processName, scrollbackLines: pane.scrollbackLines,
                    commandCount: pane.commandCount, relaunch: pane.relaunch, agent: pane.agent,
                    editor: pane.editor.map { EditorPosition(file: files.realPath($0.file), line: $0.line) })
            }, project: snapshot.project)
    }

    private func existingName(at root: String, exists: Bool) -> LayoutName? {
        guard exists else { return nil }
        do { return try LayoutName(try files.layout(at: root).layout.name) } catch { return nil }
    }

    private static func folderName(_ root: String) -> LayoutName {
        (try? LayoutName(URL(filePath: root).lastPathComponent)) ?? .project
    }
}
