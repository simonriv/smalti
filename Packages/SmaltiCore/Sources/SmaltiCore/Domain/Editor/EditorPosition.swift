/// The file and line an editor pane (Neovim) shows, saved with the session so it reopens there (spec F6).
public struct EditorPosition: Codable, Equatable, Sendable {
    public let file: String
    public let line: Int

    public init(file: String, line: Int) {
        self.file = file
        self.line = line
    }

    /// The file's name, as the restore row shows it.
    public var fileName: String { file.split(separator: "/").last.map(String.init) ?? file }

    /// `nvim +42 'file'`, relaunched in a restored pane when no socket is known.
    public var plainCommand: String { "nvim +\(line) \(ShellWord.quoted(file))" }
}
