import AppKit
import IPCAdapter
import SmaltiCore

/// F4's primary adapter on the app side: delivers each zsh message to `InputRouting` in arrival order and acts on
/// the reply. Menus open only while the pane's shell is at its prompt (OSC 133). The directory is the one zsh
/// names in the message (`$PWD`), so a `cd` never races the terminal's OSC 7; the pane's own is the fallback.
@MainActor
final class InputCoordinator {
    /// What the Tab menu and the ⌃R palette need to open and to answer zsh.
    struct Request: Equatable {
        /// Tells two Tab presses on the same line apart, so late generated items join only their own menu.
        let id = UUID()
        let pane: PaneID
        let seq: Int
        let connection: InputConnection
        let directory: String
    }

    var onMenu: ((Request, InputLine, CompletionResult) -> Void)?
    var onGenerated: ((Request, InputLine, [Suggestion]) -> Void)?
    var onHistory: ((Request, String) -> Void)?
    /// Every new line of a pane, for an open menu to refilter or close.
    var onLine: ((PaneID, InputLine) -> Void)?

    private let session: InputSession
    private let provider: any TerminalViewProvider
    private let directory: (PaneID) -> String?
    private var server: InputSocketServer?
    private var panes: [UUID: PaneID] = [:]
    private var latestSeq: [PaneID: Int] = [:]
    private var connections: [PaneID: InputConnection] = [:]
    private var events: AsyncStream<(InputConnection, ShellPacket)>.Continuation?

    init(session: InputSession, provider: any TerminalViewProvider, directory: @escaping (PaneID) -> String?) {
        self.session = session
        self.provider = provider
        self.directory = directory
    }

    func start(socketFile: URL) throws(IPCError) {
        let (stream, continuation) = AsyncStream<(InputConnection, ShellPacket)>.makeStream()
        events = continuation
        let server = try InputSocketServer(socketFile: socketFile) { connection, message in
            continuation.yield((connection, message))
        }
        server.onClose = { connection in continuation.yield((connection, ShellPacket(.bye))) }
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

    /// ⌘K's "Buscar en el historial": the palette for `pane` as if its zsh had asked with ⌃R.
    func openHistory(for pane: PaneID) {
        guard let connection = connections[pane], provider.isAtPrompt(pane) else { return }
        let path = directory(pane) ?? Self.home
        onHistory?(Request(pane: pane, seq: latestSeq[pane] ?? 0, connection: connection, directory: path), "")
    }

    /// True while no command was ever recorded (⌃R says "Historial vacío").
    var isHistoryEmpty: Bool {
        get async { await session.isHistoryEmpty }
    }

    /// ⌃R search, scoped to the pane's directory or to every directory.
    func search(_ query: String, in request: Request, everywhere: Bool) async -> [HistoryHit] {
        await session.search(query, scope: everywhere ? .all : .directory(request.directory))
    }

    /// ⌘↩: Return typed into the pane once Smalti's `edit` went out whole (otherwise the old line would run).
    func pressReturn(in pane: PaneID) {
        provider.pressReturn(pane)
    }

    /// Whether the pane's shell is at its prompt: menus close when it is not.
    func isAtPrompt(_ pane: PaneID) -> Bool { provider.isAtPrompt(pane) }

    /// The generators' items; always answered, also with nothing, so the menu can stop waiting.
    func generated(for line: InputLine, request: Request) {
        Task { [session, weak self] in
            let items = await session.generated(for: line, directory: request.directory)
            self?.onGenerated?(request, line, items)
        }
    }

    /// Sends to the pane's zsh with the last `seq` it sent: zsh drops any other. False when it did not go out whole.
    @discardableResult
    func send(_ message: (Int) -> SmaltiMessage, to request: Request) -> Bool {
        request.connection.send(message(latestSeq[request.pane] ?? request.seq))
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)

    private func handle(_ packet: ShellPacket, from connection: InputConnection) async {
        let message = packet.message
        if case .hello(let pane) = message {
            // `exec zsh` keeps the old socket open in the new shell: the newer connection replaces it.
            if let older = connections[pane], older != connection { older.close() }
            panes[connection.id] = pane
            connections[pane] = connection
        }
        guard let pane = panes[connection.id] else { return }
        if message == .bye { forget(connection, of: pane) }
        if let seq = Self.seq(of: message) { latestSeq[pane] = seq }
        if case .line(_, let line) = message { onLine?(pane, line) }
        let path = packet.directory ?? directory(pane) ?? Self.home
        let reply = await InputRouting.respond(to: message, pane: pane, directory: path, session: session)
        act(on: reply, pane: pane, connection: connection, directory: path)
    }

    /// Ends the connections of panes that no longer exist (closed panes or workspaces): a background job that
    /// outlived its shell would otherwise keep them, and their state, alive.
    func keepOnly(_ open: Set<PaneID>) {
        for (pane, connection) in connections where !open.contains(pane) {
            connection.close()
        }
    }

    private func forget(_ connection: InputConnection, of pane: PaneID) {
        panes[connection.id] = nil
        guard connections[pane] == connection else { return }
        connections[pane] = nil
        latestSeq[pane] = nil
    }

    private static func seq(of message: ShellMessage) -> Int? {
        switch message {
        case .line(let seq, _), .exec(let seq, _), .done(let seq, _), .complete(let seq, _), .history(let seq, _): seq
        case .hello, .bye: nil
        }
    }

    private func act(on reply: InputReply, pane: PaneID, connection: InputConnection, directory: String) {
        switch reply {
        case .none:
            return
        case .send(let messages):
            messages.forEach { connection.send($0) }
        case .openMenu(let seq, let line, let result):
            // Tab must always do something: if the menu cannot show, zsh runs its own Tab.
            guard provider.isAtPrompt(pane) else {
                connection.send(.fallback(seq: seq))
                return
            }
            let request = Request(pane: pane, seq: seq, connection: connection, directory: directory)
            onMenu?(request, line, result)
            if result.hasGenerators { generated(for: line, request: request) }
        case .openHistory(let seq, let query):
            guard provider.isAtPrompt(pane) else { return }
            onHistory?(Request(pane: pane, seq: seq, connection: connection, directory: directory), query)
        }
    }
}
