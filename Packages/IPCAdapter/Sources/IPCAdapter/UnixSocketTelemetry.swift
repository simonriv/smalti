import Darwin
import Foundation
import SmaltiCore
import SmaltiIPCProtocol
import Synchronization

/// `TelemetrySource` over a Unix socket (`<state>/smalti.sock`, 0600): one JSON request per connection from the
/// `smalti` CLI, answered with `{"ok":…}`. A bad request is refused without stopping the server. A socket file left
/// by a crashed instance is replaced; one a live instance answers on is never touched (`socketInUse`). Two instances
/// of the same build starting in the same instant could both see the file as stale; that window is accepted.
///
/// F7.5: a `guard` request also reports its `PreToolUse` event, then becomes a `GuardRequest` and keeps its
/// connection open until the app replies (at most `guardWaitSeconds`); stopping the server denies every open one.
@MainActor
public final class UnixSocketTelemetry: TelemetrySource, GuardRequests {
    /// How long a guard connection waits for the app's decision before it is denied.
    public nonisolated static let guardWaitSeconds = 620
    /// Guard connections allowed to wait at once; the next one is denied.
    public nonisolated static let maximumWaitingGuards = 40

    private let path: String
    private let listener: SocketListener
    private let stream = AsyncStream<AgentEvent>.makeStream()
    private let guards = AsyncStream<GuardRequest>.makeStream()
    private let waiters = GuardWaiters()

    public init(socketFile: URL, clock: @escaping @Sendable () -> Date) throws(IPCError) {
        path = socketFile.path(percentEncoded: false)
        let delivery = Delivery(
            events: stream.continuation, guards: guards.continuation, waiters: waiters, clock: clock)
        listener = try SocketListener(path: path) { line in delivery.answer(line) }
    }

    public func events() -> AsyncStream<AgentEvent> { stream.stream }

    public func requests() -> AsyncStream<GuardRequest> { guards.stream }

    /// Stops listening, denies the guard connections still waiting and removes the socket file.
    public func stop() {
        listener.stop()
        waiters.denyAll(GuardReasons.unreachable)
        stream.continuation.finish()
        guards.continuation.finish()
    }
}

/// What a connection does with its request, off the main actor.
private struct Delivery: Sendable {
    let events: AsyncStream<AgentEvent>.Continuation
    let guards: AsyncStream<GuardRequest>.Continuation
    let waiters: GuardWaiters
    let clock: @Sendable () -> Date

    func answer(_ line: Data) -> IPCResponse {
        do {
            let request = try IPCCodec.decodeRequest(line)
            guard request.version == IPCLimits.version else { return unsupported(request) }
            switch request.kind {
            case IPCRequest.eventKind:
                events.yield(try HookPayloadTranslator.event(request, at: clock()))
                return IPCResponse(ok: true, error: nil)
            case IPCRequest.guardKind:
                return try decide(request)
            default:
                return unsupported(request)
            }
        } catch {
            return IPCResponse(ok: false, error: String(describing: error))
        }
    }

    private func unsupported(_ request: IPCRequest) -> IPCResponse {
        IPCResponse(ok: false, error: "unsupported request v\(request.version) \(request.kind)")
    }

    /// Reports the event, hands the request to the app and blocks this connection's thread until it replies.
    private func decide(_ request: IPCRequest) throws(IPCError) -> IPCResponse {
        let now = clock()
        events.yield(try HookPayloadTranslator.event(request, at: now))
        guard let waiter = waiters.add() else { return response(.deny(GuardReasons.tooManyPending)) }
        defer { waiters.remove(waiter) }
        let guarded = try HookPayloadTranslator.guardRequest(request, at: now) { waiter.resolve($0) }
        guards.yield(guarded)
        return response(waiter.wait(seconds: UnixSocketTelemetry.guardWaitSeconds) ?? .deny(GuardReasons.unreachable))
    }

    private func response(_ decision: GuardDecision) -> IPCResponse {
        switch decision {
        case .allow: IPCResponse(ok: true, error: nil, decision: .allow, reason: nil)
        case .deny(let reason): IPCResponse(ok: true, error: nil, decision: .deny, reason: reason)
        }
    }
}

/// One guard connection waiting for its decision; the first decision wins.
private final class GuardWaiter: Sendable {
    let id = UUID()
    private let semaphore = DispatchSemaphore(value: 0)
    private let decision = Mutex<GuardDecision?>(nil)

    func resolve(_ value: GuardDecision) {
        let isFirst = decision.withLock { current in
            guard current == nil else { return false }
            current = value
            return true
        }
        if isFirst { semaphore.signal() }
    }

    func wait(seconds: Int) -> GuardDecision? {
        _ = semaphore.wait(timeout: .now() + .seconds(seconds))
        return decision.withLock { $0 }
    }
}

/// The guard connections waiting now, so stopping can deny them and their number stays bounded.
private final class GuardWaiters: Sendable {
    private let waiting = Mutex<[UUID: GuardWaiter]>([:])

    func add() -> GuardWaiter? {
        waiting.withLock { all in
            guard all.count < UnixSocketTelemetry.maximumWaitingGuards else { return nil }
            let waiter = GuardWaiter()
            all[waiter.id] = waiter
            return waiter
        }
    }

    func remove(_ waiter: GuardWaiter) {
        _ = waiting.withLock { $0.removeValue(forKey: waiter.id) }
    }

    func denyAll(_ reason: String) {
        let all = waiting.withLock { Array($0.values) }
        for waiter in all { waiter.resolve(.deny(reason)) }
    }
}

/// The socket itself: accepts on a background queue and serves each connection there.
private final class SocketListener: @unchecked Sendable {
    /// A client that sends nothing for this long is dropped.
    private static let readTimeoutSeconds = 1
    private let fd: Int32
    private let path: String
    private let source: DispatchSourceRead
    private let queue = DispatchQueue(label: "dev.simonriv.smalti.ipc")
    /// Each connection is served on its own, so a client that says nothing cannot hold up the others.
    private let connections = DispatchQueue(label: "dev.simonriv.smalti.ipc.connections", attributes: .concurrent)
    private let stopped = Mutex(false)

    init(path: String, handle: @escaping @Sendable (Data) -> IPCResponse) throws(IPCError) {
        try UnixSocketFile.checkLength(path)
        try UnixSocketFile.claim(path)
        self.path = path
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .socketFailed(operation: "socket", path: path, code: errno) }
        // Accepted connections inherit it: a client that hangs up never raises SIGPIPE in the app.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        do {
            try UnixSocketFile.bind(fd, to: path)
        } catch {
            close(fd)
            unlink(path)
            throw error
        }
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let listening = fd
        let connections = self.connections
        source.setEventHandler {
            let client = accept(listening, nil, nil)
            connections.async { Self.serve(client, handle: handle) }
        }
        source.setCancelHandler { close(listening) }
        source.resume()
    }

    deinit {
        stop()
    }

    /// Stops listening and removes the socket file, once.
    func stop() {
        let wasStopped = stopped.withLock { done in
            defer { done = true }
            return done
        }
        guard !wasStopped else { return }
        source.cancel()
        unlink(path)
    }

    private static func serve(_ client: Int32, handle: (Data) -> IPCResponse) {
        guard client >= 0 else { return }
        defer { close(client) }
        // A client that hangs up early (a probe, a killed CLI) must not take the app down with SIGPIPE.
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: readTimeoutSeconds, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let response =
            readLine(client).map(handle)
            ?? IPCResponse(ok: false, error: "message over \(IPCLimits.maxMessageBytes) bytes")
        guard let data = try? IPCCodec.encode(response) else { return }
        _ = data.withUnsafeBytes { write(client, $0.baseAddress, data.count) }
    }

    /// The request up to its newline or the end of the stream; nil when it exceeds the limit.
    private static func readLine(_ client: Int32) -> Data? {
        var line = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return line }
            line.append(contentsOf: buffer.prefix(count))
            if line.count > IPCLimits.maxMessageBytes + 1 { return nil }
            if let end = line.firstIndex(of: UInt8(ascii: "\n")) { return line.prefix(upTo: end) }
        }
    }
}
