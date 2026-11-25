/// Where "Abrir en Neovim" goes: a file, and the line and column when a `ruta:línea[:columna]` names them.
public struct EditorTarget: Equatable, Sendable {
    public let path: String
    public let line: Int?
    public let column: Int?

    public init(path: String, line: Int?, column: Int?) {
        self.path = path
        self.line = line
        self.column = column
    }

    /// `src/a.ts:12:3` under `cwd` → `/cwd/src/a.ts`, line 12, column 3. URLs and empty paths are not targets.
    public static func parse(_ word: String, cwd: String, home: String? = nil) -> EditorTarget? {
        guard !word.contains("://") else { return nil }
        var parts = word.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var numbers: [Int?] = []
        while parts.count > 1, let last = parts.last, last.isEmpty || Int(last) != nil, numbers.count < 2 {
            numbers.insert(Int(last).flatMap { $0 > 0 ? $0 : nil }, at: 0)
            parts.removeLast()
        }
        let path = parts.joined(separator: ":")
        guard !path.isEmpty else { return nil }
        let line = numbers.first ?? nil
        let column = line == nil ? nil : (numbers.count > 1 ? numbers[1] : nil)
        return EditorTarget(path: absolute(path, cwd: cwd, home: home), line: line, column: column)
    }

    private static func absolute(_ path: String, cwd: String, home: String?) -> String {
        if path.hasPrefix("/") { return path }
        if let home, path == "~" || path.hasPrefix("~/") { return home + path.dropFirst() }
        let base = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        let relative = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        return base + "/" + relative
    }
}

/// Why an editor could not be reached or told to open a file.
public enum EditorError: Error, Equatable, Sendable {
    case socketPathTooLong(path: String)
    case unreachable(socket: String, reason: String)
    case rejected(socket: String, reason: String)
}

/// Each Smalti Neovim pane listens on its own socket, under a short directory: `sun_path` holds 104 bytes.
public enum EditorSocketPath {
    public static let maximumBytes = 104

    public static func make(directory: String, pane: PaneID) throws(EditorError) -> String {
        let base = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        let path = "\(base)/nvim-\(pane.rawValue.uuidString.lowercased()).sock"
        guard path.utf8.count < maximumBytes else { throw .socketPathTooLong(path: path) }
        return path
    }
}

/// The command a new Neovim pane runs: `nvim --listen <socket> +12 <file>`.
public enum EditorCommand {
    public static func launch(nvim: String, socket: String, target: EditorTarget?) -> String {
        var words = [nvim, "--listen", ShellWord.quoted(socket)]
        if let line = target?.line { words.append("+\(line)") }
        if let target { words.append(ShellWord.quoted(target.path)) }
        return words.joined(separator: " ")
    }

    /// A saved Neovim pane reopens at its file and line, listening on its pane's socket again; without a usable socket
    /// it still reopens there, as a plain `nvim +42 <file>`.
    public static func reopen(nvim: String, socketDirectory: String, position: EditorPosition, pane: PaneID) -> String {
        guard let socket = try? EditorSocketPath.make(directory: socketDirectory, pane: pane) else {
            return position.plainCommand
        }
        return launch(
            nvim: nvim, socket: socket, target: EditorTarget(path: position.file, line: position.line, column: nil))
    }
}
