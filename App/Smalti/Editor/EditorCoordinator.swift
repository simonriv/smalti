import Foundation
import SmaltiCore

/// What the editor coordinator needs from its window's tiling.
@MainActor
protocol EditorHost: AnyObject {
    /// The panes of the workspace that holds `pane`.
    func panes(nearEditorOf pane: PaneID) -> [Pane]
    func pane(byID id: PaneID) -> Pane?
    /// Opens a pane next to `beside` running `command` in `directory`; nil when it could not open.
    func openEditorPane(command: String, directory: WorkingDirectory, beside: PaneID) -> PaneID?
    @discardableResult func activate(_ pane: PaneID) -> Bool
    /// A line in the status bar.
    func report(_ text: String)
}

/// F6, Neovim in a window: the panes Smalti opened with a socket, which one had the focus last, "Abrir Neovim junto
/// al agente", "Abrir en Neovim" (from ⌘K, ⌘⇧L and ⌘-click) and, for saving, each pane's socket.
@MainActor
final class EditorCoordinator: EditorPanes {
    /// Lines a file must not hold NUL bytes in to count as text (spec F6: binaries keep F4.5's ⌘-click).
    static let textProbeBytes = 8 * 1024

    let editedFiles: TrackEditedFiles
    weak var host: EditorHost?
    private let nvim: String
    private let socketDirectory: String
    private let home: String
    private let bridge: any EditorBridge
    private lazy var opener = OpenInEditor(bridge: bridge, panes: self, socketDirectory: socketDirectory, nvim: nvim)
    private var sockets: [PaneID: String] = [:]
    private var focusOrder: [PaneID] = []

    init(settings: EditorSettings, home: String) {
        editedFiles = settings.editedFiles
        nvim = settings.nvim
        socketDirectory = settings.socketDirectory
        bridge = settings.bridge
        self.home = home
    }

    // MARK: - EditorPanes

    func editors(near pane: PaneID) -> [(pane: PaneID, socket: String)] {
        let near = host?.panes(nearEditorOf: pane) ?? []
        let live = near.filter { $0.processName == "nvim" }.compactMap { pane in sockets[pane.id].map { (pane.id, $0) }
        }
        return live.sorted { rank($0.0) < rank($1.0) }.map { (pane: $0.0, socket: $0.1) }
    }

    private func rank(_ pane: PaneID) -> Int { focusOrder.firstIndex(of: pane) ?? Int.max }

    // MARK: - Actions

    func noteFocus(_ pane: PaneID?) {
        guard let pane, sockets[pane] != nil else { return }
        focusOrder.removeAll { $0 == pane }
        focusOrder.insert(pane, at: 0)
    }

    func forget(_ pane: PaneID) {
        sockets[pane] = nil
        focusOrder.removeAll { $0 == pane }
        editedFiles.forget(pane)
    }

    func socket(of pane: PaneID) -> String? { sockets[pane] }

    /// F6, for saving: the file and line of each Smalti Neovim still running, asked all at once (200 ms each); one
    /// that does not answer is left out and saves as its process.
    func positions() async -> [PaneID: EditorPosition] {
        let live = sockets.filter { host?.pane(byID: $0.key)?.processName == "nvim" }
        var found: [PaneID: EditorPosition] = [:]
        await withTaskGroup(of: (PaneID, EditorPosition?).self) { group in
            for (pane, socket) in live {
                group.addTask { [bridge] in (pane, await bridge.current(socket: socket)) }
            }
            for await (pane, position) in group { found[pane] = position }
        }
        return found
    }

    /// F6: a restored Neovim pane listens on `socket` again.
    func adopt(_ pane: PaneID, socket: String) {
        sockets[pane] = socket
    }

    /// ⌘⇧E: a Neovim with its socket next to `pane`, in its directory.
    func openBeside(_ pane: PaneID) {
        guard let origin = host?.pane(byID: pane),
            let socket = try? EditorSocketPath.make(directory: socketDirectory, pane: PaneID())
        else { return }
        let command = EditorCommand.launch(nvim: nvim, socket: socket, target: nil)
        if let opened = host?.openEditorPane(command: command, directory: origin.workingDirectory, beside: pane) {
            sockets[opened] = socket
            noteFocus(opened)
        }
    }

    /// ⌘⇧L: the newest file `pane`'s Claude edited (its workspace's, from a pane without edits).
    func openLastEdited(from pane: PaneID) {
        let workspace = host?.panes(nearEditorOf: pane).map(\.id) ?? []
        guard let file = editedFiles.recent(in: pane, workspace: workspace).first else {
            host?.report(EditedFiles.noneText)
            return
        }
        open(EditorTarget(path: file.path, line: file.line, column: nil), from: pane)
    }

    func open(_ target: EditorTarget, from pane: PaneID) {
        Task { [weak self] in
            guard let self else { return }
            switch await opener.open(target, from: pane) {
            case .jumped(let editor):
                host?.activate(editor)
                noteFocus(editor)
            case .opened(let socket, let command, let beside):
                guard let origin = host?.pane(byID: beside),
                    let opened = host?.openEditorPane(
                        command: command, directory: origin.workingDirectory, beside: beside)
                else { return }
                sockets[opened] = socket
                noteFocus(opened)
            case .ignored:
                break
            }
        }
    }

    /// ⌘-click: a regular text file under the click opens in Neovim; anything else stays the terminal's.
    func commandClick(on word: String, in pane: PaneID) -> Bool {
        guard let origin = host?.pane(byID: pane),
            let target = EditorTarget.parse(word, cwd: origin.workingDirectory.path, home: home),
            Self.isTextFile(target.path)
        else { return false }
        open(target, from: pane)
        return true
    }

    /// Only a regular file is opened to probe: opening a named pipe for reading would block the main thread.
    static func isTextFile(_ path: String) -> Bool {
        let isRegular = (try? URL(filePath: path).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        guard isRegular, let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: textProbeBytes)) ?? Data()
        return !head.contains(0)
    }
}
