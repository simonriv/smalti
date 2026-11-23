import AppKit
import IPCAdapter
import SmaltiCore

/// F4's primary adapter on the app side: delivers each zsh message to `InputRouting` in arrival order and acts on
/// the reply. Menus open only while the pane's shell is at its prompt (OSC 133); the directory is the pane's own
/// (OSC 7) when the message arrives.
@MainActor
final class InputCoordinator {
    /// What the Tab menu and the ⌃R palette need to open and to answer zsh.
    struct Request {
        let pane: PaneID
        let seq: Int
        let connection: InputConnection
    }

    var onMenu: ((Request, InputLine, CompletionResult) -> Void)?
    var onGenerated: ((Request, InputLine, [Suggestion]) -> Void)?
    var onHistory: ((Request, String) -> Void)?

    private let session: InputSession
    private let provider: any TerminalViewProvider
    private let directory: (PaneID) -> String?
    private var server: InputSocketServer?
    private var panes: [UUID: PaneID] = [:]
    private var events: AsyncStream<(InputConnection, ShellMessage)>.Continuation?

    init(session: InputSession, provider: any TerminalViewProvider, directory: @escaping (PaneID) -> String?) {
        self.session = session
        self.provider = provider
        self.directory = directory
    }

    func start(socketFile: URL) throws(IPCError) {
        let (stream, continuation) = AsyncStream<(InputConnection, ShellMessage)>.makeStream()
        events = continuation
        let server = try InputSocketServer(socketFile: socketFile) { connection, message in
            continuation.yield((connection, message))
        }
        server.onClose = { connection in continuation.yield((connection, .bye)) }
        self.server = server
        Task { [session] in await session.start() }
        Task { [weak self] in
            for await (connection, message) in stream { await self?.handle(message, from: connection) }
        }
    }

    func stop() {
        server?.stop()
        events?.finish()
    }

    /// Whether the pane's shell is at its prompt: menus close when it is not.
    func isAtPrompt(_ pane: PaneID) -> Bool { provider.isAtPrompt(pane) }

    func generated(for line: InputLine, request: Request) {
        guard let path = directory(request.pane) else { return }
        Task { [session, weak self] in
            let items = await session.generated(for: line, directory: path)
            self?.onGenerated?(request, line, items)
        }
    }

    private func handle(_ message: ShellMessage, from connection: InputConnection) async {
        if case .hello(let pane) = message { panes[connection.id] = pane }
        guard let pane = panes[connection.id] else { return }
        if message == .bye { panes[connection.id] = nil }
        let path = directory(pane) ?? "/"
        let reply = await InputRouting.respond(to: message, pane: pane, directory: path, session: session)
        act(on: reply, pane: pane, connection: connection)
    }

    private func act(on reply: InputReply, pane: PaneID, connection: InputConnection) {
        switch reply {
        case .none:
            return
        case .send(let messages):
            messages.forEach { connection.send($0) }
        case .openMenu(let seq, let line, let result):
            guard provider.isAtPrompt(pane) else { return }
            let request = Request(pane: pane, seq: seq, connection: connection)
            onMenu?(request, line, result)
            if result.hasGenerators { generated(for: line, request: request) }
        case .openHistory(let seq, let query):
            guard provider.isAtPrompt(pane) else { return }
            onHistory?(Request(pane: pane, seq: seq, connection: connection), query)
        }
    }
}
