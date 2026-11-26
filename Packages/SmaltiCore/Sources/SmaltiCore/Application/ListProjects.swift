import Foundation

/// A project as ⌘K and ⌘O list it.
public struct ProjectListing: Equatable, Sendable {
    public let root: String
    public let name: String
    /// When it was last opened; `nil` for a project only discovered from a pane.
    public let lastOpened: Date?
    public let isInFocusedPane: Bool
    public let openIn: OpenProjectWorkspace?
}

/// The projects to offer (F8.5): the recents whose file still exists and the ones discovered from the panes' folders,
/// each once. The focused pane's comes first, then the recents newest first, then the rest by name. It runs only when
/// ⌘K or ⌘O opens, after `forgetMissing`.
@MainActor
public struct ListProjects {
    private let files: any ProjectFiles
    private let records: any ProjectRecords
    private let discovery: ProjectDiscovery

    public init(files: any ProjectFiles, records: any ProjectRecords, home: String) {
        self.files = files
        self.records = records
        discovery = ProjectDiscovery(files: files, home: home)
    }

    public func execute(paneDirectories: [String], focusedDirectory: String?, open: [OpenProjectWorkspace])
        -> [ProjectListing]
    {
        let recents = RecentProjects(records: records.all()).pruned { files.hasLayout(in: $0) }.0
        let focused = focusedDirectory.flatMap(discoveredRoot)
        var listed = recents.ordered.map { listing($0.root, $0.name, $0.lastOpened, focused: focused, open: open) }
        let known = Set(listed.map(\.root))
        let discovered = Set(paneDirectories.compactMap(discoveredRoot)).subtracting(known)
        listed += discovered.map { listing($0, discoveredName($0), nil, focused: focused, open: open) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return listed.filter(\.isInFocusedPane) + listed.filter { !$0.isInFocusedPane }
    }

    /// Forgets the recents whose repo no longer has its file; returns how many. Writes only when one went.
    @discardableResult
    public func forgetMissing() throws(ProjectFileError) -> Int {
        let (kept, removed) = RecentProjects(records: records.all()).pruned { files.hasLayout(in: $0) }
        if removed > 0 { try records.replace(with: kept.ordered) }
        return removed
    }

    private func discoveredRoot(_ directory: String) -> String? {
        discovery.root(containing: files.realPath(directory)).map(files.realPath)
    }

    private func discoveredName(_ root: String) -> String {
        do { return try files.layout(at: root).layout.name } catch {
            return URL(filePath: root).lastPathComponent
        }
    }

    private func listing(
        _ root: String, _ name: String, _ lastOpened: Date?, focused: String?, open: [OpenProjectWorkspace]
    ) -> ProjectListing {
        ProjectListing(
            root: root, name: name, lastOpened: lastOpened, isInFocusedPane: root == focused,
            openIn: open.first { $0.project == root })
    }
}
