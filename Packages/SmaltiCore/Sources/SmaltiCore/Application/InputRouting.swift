/// What the app does with one message from a pane's zsh: answer it, open the Tab menu or open the ⌃R palette.
public enum InputReply: Equatable, Sendable {
    case none
    case send([SmaltiMessage])
    case openMenu(seq: Int, line: InputLine, result: CompletionResult)
    case openHistory(seq: Int, query: String)
}

/// Turns each shell message into the use case it asks for. It lives here, not in the app, so it is tested without
/// AppKit; the app only delivers the messages and acts on the reply. `directory` is the pane's directory when the
/// message arrived (OSC 7), so a `cd` just before is never mixed with an older answer.
public enum InputRouting {
    public static func respond(
        to message: ShellMessage, pane: PaneID, directory: String, session: InputSession
    ) async -> InputReply {
        switch message {
        case .hello:
            return .send(InputProtocol.specMessages(await session.specCommands))
        case .line(let seq, let line):
            return .send([.suggest(seq: seq, await session.suggest(line, pane: pane, directory: directory))])
        case .exec(_, let command):
            await session.began(command, pane: pane, directory: directory)
            return .none
        case .done(_, let exit):
            await session.finished(pane: pane, exit: exit)
            return .none
        case .complete(let seq, let line):
            guard let result = await session.complete(line, directory: directory),
                !result.items.isEmpty || result.hasGenerators
            else { return .send([.fallback(seq: seq)]) }
            return .openMenu(seq: seq, line: line, result: result)
        case .history(let seq, let query):
            return .openHistory(seq: seq, query: query)
        case .context:
            // F5: the app hands `context` to `RenderPrompt` (spec F5, T17); nothing to route here.
            return .none
        case .bye:
            return .none
        }
    }
}

/// F5.6: a `line` to highlight, with the shell's `seq` and where relative paths and `~` resolve.
public struct HighlightRequest: Sendable {
    public let line: InputLine
    public let seq: Int
    public let directory: String
    public let home: String

    public init(line: InputLine, seq: Int, directory: String, home: String) {
        self.line = line
        self.seq = seq
        self.directory = directory
        self.home = home
    }
}

extension InputRouting {
    /// The highlight to send right away; `needsFollowUp` when a spec or a slow path was still missing.
    public static func highlight(_ request: HighlightRequest, using highlighter: HighlightLine) async
        -> (first: SmaltiMessage, needsFollowUp: Bool)
    {
        let answer = await highlighter.firstAnswer(request.line, directory: request.directory, home: request.home)
        return (.highlight(seq: request.seq, answer.spans), !answer.isComplete)
    }

    /// The complete highlight, replacing the first one in zsh when it is still about the same line.
    public static func followUp(_ request: HighlightRequest, using highlighter: HighlightLine) async -> SmaltiMessage {
        .highlight(
            seq: request.seq,
            await highlighter.completeAnswer(request.line, directory: request.directory, home: request.home))
    }

    /// A late answer is only worth sending while its line is still the shell's last one.
    public static func shouldSendFollowUp(seq: Int, latest: Int?) -> Bool {
        latest == seq
    }
}
