/// A pane's saved output: VT text with colours, or plain text when colours could not be exported.
public struct Scrollback: Hashable, Sendable {
    public enum Format: String, Codable, Sendable {
        case vt, plain
    }

    public let text: String
    public let format: Format

    public init(text: String, format: Format) {
        self.text = text
        self.format = format
    }

    public var lineCount: Int { text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count }
}

public enum ScrollbackError: Error, Equatable, Sendable {
    case unavailable(pane: PaneID, reason: String)
}

/// Port: reads a live pane's scrollback (the terminal engine).
@MainActor
public protocol ScrollbackSource: AnyObject {
    func scrollback(of pane: PaneID, lastLines: Int) throws(ScrollbackError) -> Scrollback
}
