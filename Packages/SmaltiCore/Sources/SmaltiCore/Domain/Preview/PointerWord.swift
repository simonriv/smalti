/// The word under the mouse pointer in a pane, as the engine cut it, and where it sits in the pane's view (points).
public struct PointerWord: Equatable, Sendable {
    public let text: String
    public let frame: Rect

    public init(text: String, frame: Rect) {
        self.text = text
        self.frame = frame
    }
}

/// What a pane knows to resolve a word into a file: its directory (OSC 7), the user's home and its last command.
public struct PreviewContext: Equatable, Sendable {
    public let workingDirectory: String?
    public let home: String
    public let lastCommand: String?

    public init(workingDirectory: String?, home: String, lastCommand: String?) {
        self.workingDirectory = workingDirectory
        self.home = home
        self.lastCommand = lastCommand
    }
}
