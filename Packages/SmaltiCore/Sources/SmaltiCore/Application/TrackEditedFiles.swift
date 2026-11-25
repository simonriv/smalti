import Foundation

/// Keeps "Editados por Claude" per pane from the `PostToolUse` events of file tools (spec F6).
@MainActor
public final class TrackEditedFiles {
    private let readFile: (String) -> String?
    private var files: [PaneID: EditedFiles] = [:]

    /// `readFile` gives a file's text, to find the line of the change.
    public init(readFile: @escaping (String) -> String?) {
        self.readFile = readFile
    }

    public func record(_ event: AgentEvent) {
        guard let edit = event.edit else { return }
        let line = Self.lineOf(newText: edit.newText, in: readFile(edit.path) ?? "")
        files[event.pane, default: EditedFiles()].record(edit, line: line, at: event.at)
    }

    public func recent(in pane: PaneID) -> [EditedFile] { files[pane]?.recent ?? [] }

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
