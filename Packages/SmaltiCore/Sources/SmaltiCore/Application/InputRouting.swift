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
        case .bye:
            return .none
        }
    }
}
