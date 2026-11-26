import Foundation

/// Why a shared layout file cannot be imported. `message` is the reason the status bar shows.
public enum SharedLayoutError: Error, Equatable, Sendable {
    case unsupportedFormat(Int)
    /// F7.6: exported by a newer Smalti.
    case newerFormat(Int)
    case invalidName(String, reason: String)
    case paneCount(Int)
    case treeMismatch(leaves: Int, panes: Int)
    /// `pane` counts from 1, as the confirmation and the messages say it.
    case untypeableCommand(pane: Int)
    case emptyCommand(pane: Int)
    case escapingDirectory(pane: Int, path: String)
    case tooLarge(bytes: Int)
    case notJSON(reason: String)
    /// A pane that names more than one of `command`, `harness` and `editor`: which one runs would be ambiguous.
    case ambiguousPane(pane: Int)
    case invalidEditor(pane: Int)
    /// The tree's leaves are not each pane exactly once.
    case invalidTree
    case invalidRoot(String)

    public func message(_ texts: SharedLayoutErrorTexts) -> String {
        switch self {
        case .unsupportedFormat(let format): texts.unsupportedFormat(["format": String(format)])
        case .newerFormat(let format): texts.newerFormat(["format": String(format)])
        case .invalidName(let name, let reason): texts.invalidName(["name": name, "reason": reason])
        case .paneCount(0): texts.noPanes
        case .paneCount(let count):
            texts.tooManyPanes(["count": String(count), "maximum": String(SharedLayout.maximumPanes)])
        case .treeMismatch(let leaves, let panes):
            texts.treeMismatch(["leaves": String(leaves), "panes": String(panes)])
        case .untypeableCommand(let pane): texts.untypeableCommand(["pane": String(pane)])
        case .emptyCommand(let pane): texts.emptyCommand(["pane": String(pane)])
        case .escapingDirectory(let pane, let path): texts.escapingDirectory(["pane": String(pane), "path": path])
        case .tooLarge(let bytes):
            texts.tooLarge(["bytes": String(bytes), "maximum": String(SharedLayout.maximumBytes)])
        case .notJSON(let reason): texts.notJSON(["reason": reason])
        case .ambiguousPane(let pane): texts.ambiguousPane(["pane": String(pane)])
        case .invalidEditor(let pane): texts.invalidEditor(["pane": String(pane)])
        case .invalidTree: texts.invalidTree
        case .invalidRoot(let root): texts.invalidRoot(["root": root])
        }
    }
}

/// What an import degrades instead of refusing: the confirmation says it.
public enum SharedLayoutWarning: Equatable, Sendable {
    case unknownHarness(pane: Int, name: String)
    case unknownLayout(String)
}

/// A Neovim pane's file, relative to its pane's directory when inside it.
public struct SharedEditor: Codable, Equatable, Sendable {
    public let file: String
    public let line: Int

    public init(file: String, line: Int) {
        self.file = file
        self.line = line
    }
}

/// One pane of a shared layout: where it opens and what it runs, without identity or history.
public struct SharedPane: Codable, Equatable, Sendable {
    /// Relative to the layout's root (`.`, `api`), or `~/…` / absolute when outside it.
    public let directory: String
    public let command: [String]?
    /// Any name decodes: a harness this Smalti does not know is a warning, not a broken file.
    public let harness: HarnessID?
    public let editor: SharedEditor?

    public init(directory: String, command: [String]? = nil, harness: HarnessID? = nil, editor: SharedEditor? = nil) {
        self.directory = directory
        self.command = command
        self.harness = harness
        self.editor = editor
    }
}

/// A shared layout that passed validation, with what it degrades.
public struct ValidatedLayout: Equatable, Sendable {
    public let name: LayoutName
    public let layout: SharedLayout
    public let warnings: [SharedLayoutWarning]
}

/// A named layout as a portable file (spec F7, format 1): paths relative to its root, the root with `~`, and no pane
/// identities, session IDs, titles or scrollback.
public struct SharedLayout: Codable, Equatable, Sendable {
    public static let formatVersion = 1
    public static let maximumPanes = 9
    public static let maximumBytes = 262_144
    public static let fileExtension = "smalti-layout.json"

    public var smaltiLayout: Int
    public var name: String
    public var root: String
    public var layout: String
    public var focused: Int?
    public var tree: SnapshotTree?
    public var panes: [SharedPane]

    public init(
        smaltiLayout: Int, name: String, root: String, layout: String, focused: Int?, tree: SnapshotTree?,
        panes: [SharedPane]
    ) {
        self.smaltiLayout = smaltiLayout
        self.name = name
        self.root = root
        self.layout = layout
        self.focused = focused
        self.tree = tree
        self.panes = panes
    }

    public init(exporting snapshot: WorkspaceSnapshot, named name: LayoutName, home: String) {
        let paths = PortablePaths(home: home)
        self.init(
            smaltiLayout: Self.formatVersion, name: name.rawValue, root: paths.portable(snapshot.rootDirectory),
            layout: snapshot.layout, focused: snapshot.focusedIndex, tree: snapshot.tree,
            panes: snapshot.panes.map { Self.sharedPane($0, root: snapshot.rootDirectory, paths: paths) })
    }

    private static func sharedPane(_ pane: PaneSnapshot, root: String, paths: PortablePaths) -> SharedPane {
        let editor = pane.editor.map {
            SharedEditor(
                file: PortablePaths.relative($0.file, to: pane.workingDirectory) ?? paths.portable($0.file),
                line: $0.line)
        }
        return SharedPane(
            directory: PortablePaths.relative(pane.workingDirectory, to: root) ?? paths.portable(pane.workingDirectory),
            command: pane.relaunch?.arguments.map(paths.portableArgument), harness: pane.agent?.harness, editor: editor)
    }

    /// The root on this machine: `~` is this user's home.
    public func resolvedRoot(home: String) -> String { PortablePaths(home: home).absolute(root, base: home) }

    public func validated() throws(SharedLayoutError) -> ValidatedLayout {
        switch FormatCompatibility.of(stored: smaltiLayout, current: Self.formatVersion) {
        case .current: break
        case .newer(let format): throw .newerFormat(format)
        case .older(let format): throw .unsupportedFormat(format)
        }
        let layoutName: LayoutName
        do {
            layoutName = try LayoutName(name)
        } catch {
            guard case .invalid(_, let reason) = error else { throw .invalidName(name, reason: "") }
            throw .invalidName(name, reason: reason)
        }
        guard root == "~" || root.hasPrefix("~/") || root.hasPrefix("/") else { throw .invalidRoot(root) }
        guard (1...Self.maximumPanes).contains(panes.count) else { throw .paneCount(panes.count) }
        if let tree {
            guard tree.leafCount == panes.count else { throw .treeMismatch(leaves: tree.leafCount, panes: panes.count) }
            guard tree.leafIndices.sorted() == Array(panes.indices) else { throw .invalidTree }
        }
        for (index, pane) in panes.enumerated() { try Self.check(pane, number: index + 1) }
        return ValidatedLayout(name: layoutName, layout: self, warnings: warnings)
    }

    private static func check(_ pane: SharedPane, number: Int) throws(SharedLayoutError) {
        // The confirmation shows one program per pane: a file naming two could show one and run the other.
        let programs = [pane.command != nil, pane.harness != nil, pane.editor != nil].count { $0 }
        guard programs <= 1 else { throw .ambiguousPane(pane: number) }
        if let command = pane.command {
            guard let first = command.first, !first.isEmpty else { throw .emptyCommand(pane: number) }
            guard RelaunchCommand.isTypeable(command) else { throw .untypeableCommand(pane: number) }
        }
        if PortablePaths.escapesUpward(pane.directory) {
            throw .escapingDirectory(pane: number, path: pane.directory)
        }
        if let editor = pane.editor {
            // The file is typed into the shell (`nvim +N 'file'`): a control character would edit or run the line.
            guard !editor.file.isEmpty, editor.line >= 1, RelaunchCommand.isTypeable([editor.file]) else {
                throw .invalidEditor(pane: number)
            }
            if PortablePaths.escapesUpward(editor.file) { throw .escapingDirectory(pane: number, path: editor.file) }
        }
    }

    private var warnings: [SharedLayoutWarning] {
        var warnings: [SharedLayoutWarning] = panes.enumerated().compactMap { index, pane in
            guard let harness = pane.harness, !harness.isKnown else { return nil }
            return .unknownHarness(pane: index + 1, name: harness.rawValue)
        }
        if LayoutCatalog.standard.strategy(for: LayoutID(rawValue: layout)) == nil {
            warnings.append(.unknownLayout(layout))
        }
        return warnings
    }

    /// The saved workspace this file stands for under `root`, with fresh pane identities and nothing to replay. Call
    /// it on a validated layout: an unknown harness becomes a shell and an unknown layout Dwindle.
    public func workspaceSnapshot(root: String, home: String) -> WorkspaceSnapshot {
        let paths = PortablePaths(home: home)
        let isKnownLayout = LayoutCatalog.standard.strategy(for: LayoutID(rawValue: layout)) != nil
        let restored = panes.map { pane in
            let directory = paths.absolute(pane.directory, base: root)
            return PaneSnapshot(
                id: UUID(), workingDirectory: directory, title: nil, processName: nil, scrollbackLines: 0,
                commandCount: 0,
                relaunch: pane.command.map { RelaunchCommand(arguments: $0.map(paths.expandedArgument)) },
                agent: pane.harness.flatMap {
                    $0.isKnown ? AgentSnapshot(harness: $0, sessionID: nil, title: nil, lastState: nil) : nil
                },
                editor: pane.editor.map {
                    EditorPosition(file: paths.absolute($0.file, base: directory), line: $0.line)
                })
        }
        return WorkspaceSnapshot(
            name: name, rootDirectory: root, layout: isKnownLayout ? layout : LayoutID.dwindle.rawValue, tree: tree,
            focusedIndex: focused.flatMap { panes.indices.contains($0) ? $0 : nil }, panes: restored)
    }
}

/// Paths written so that they mean the same on another Mac: relative, under `~`, or absolute as a last resort.
struct PortablePaths {
    let home: String

    init(home: String) {
        self.home = Self.trimmed(home)
    }

    func portable(_ path: String) -> String {
        if path == home { return "~" }
        return Self.relative(path, to: home).map { "~/" + $0 } ?? path
    }

    /// A command argument with this home written as `~` wherever a path starts in it: at the start, after `=` or
    /// after `:` (`--config=~/x`, `PATH=~/bin:/usr/bin`), so the file never carries the home's path.
    func portableArgument(_ argument: String) -> String {
        Self.replacingAtPathStarts(in: argument, token: home, with: "~")
    }

    /// The inverse of `portableArgument` with this machine's home: the shell will not expand a quoted `~`.
    func expandedArgument(_ argument: String) -> String {
        Self.replacingAtPathStarts(in: argument, token: "~", with: home)
    }

    /// `token` replaced where a path starts (start of the argument, after `=` or `:`) and ends a component (followed
    /// by the end, `/` or `:`): `/Users/simonx` is not the home `/Users/simon`, nor is `~user` the `~`.
    private static func replacingAtPathStarts(in argument: String, token: String, with replacement: String) -> String {
        var result = ""
        var rest = Substring(argument)
        var isPathStart = true
        while let next = rest.first {
            if isPathStart, rest.hasPrefix(token) {
                let after = rest.dropFirst(token.count)
                if after.first.map({ $0 == "/" || $0 == ":" }) ?? true {
                    result += replacement
                    rest = after
                    isPathStart = false
                    continue
                }
            }
            result.append(next)
            isPathStart = next == "=" || next == ":"
            rest = rest.dropFirst()
        }
        return result
    }

    func absolute(_ path: String, base: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        if path.hasPrefix("/") { return path }
        let base = Self.trimmed(base)
        return path == "." ? base : base + "/" + path
    }

    /// `path` relative to `base` when it is `base` itself (`.`) or below it; `nil` otherwise.
    static func relative(_ path: String, to base: String) -> String? {
        let base = trimmed(base)
        if path == base { return "." }
        let prefix = base + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }

    /// A relative path with a `..` component could reach outside the layout's folder.
    static func escapesUpward(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.hasPrefix("~") && path.split(separator: "/").contains("..")
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
