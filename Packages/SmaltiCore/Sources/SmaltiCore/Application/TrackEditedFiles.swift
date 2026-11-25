import Foundation

/// Keeps "Editados por Claude" per pane from the `PostToolUse` events of file tools (spec F6).
@MainActor
public final class TrackEditedFiles {
    private let readFile: @Sendable (String) -> String?
    private var files: [PaneID: EditedFiles] = [:]

    /// `readFile` gives (the start of) a file's text, to find the line of the change; it runs off the main actor.
    public init(readFile: @escaping @Sendable (String) -> String?) {
        self.readFile = readFile
    }

    public func record(_ event: AgentEvent) async {
        guard let edit = event.edit else { return }
        let read = readFile
        let line = await Task.detached { Self.lineOf(newText: edit.newText, in: read(edit.path) ?? "") }.value
        files[event.pane, default: EditedFiles()].record(edit, line: line, at: event.at)
    }

    public func recent(in pane: PaneID) -> [EditedFile] { files[pane]?.recent ?? [] }

    /// `pane`'s edits; a pane without any (the Neovim ⌘⇧E just focused) shows its workspace's, newest first, each
    /// file once, up to the same limit.
    public func recent(in pane: PaneID, workspace: [PaneID]) -> [EditedFile] {
        let own = recent(in: pane)
        guard own.isEmpty else { return own }
        let merged = workspace.flatMap { recent(in: $0) }.sorted { $0.at > $1.at }
        var seen: Set<String> = []
        return Array(merged.filter { seen.insert($0.path).inserted }.prefix(EditedFiles.limit))
    }

    public func forget(_ pane: PaneID) { files[pane] = nil }

    /// The first line holding the change's first non-empty line; 1 when it is not found.
    nonisolated public static func lineOf(newText: String?, in fileText: String) -> Int {
        let needle = newText?.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let needle else { return 1 }
        let lines = fileText.split(separator: "\n", omittingEmptySubsequences: false)
        return (lines.firstIndex { $0.contains(needle) }).map { $0 + 1 } ?? 1
    }
}
