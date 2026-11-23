import Darwin
import Foundation
import SmaltiCore
import SmaltiIPCProtocol
import Synchronization

/// `TelemetrySource` over a Unix socket (`<state>/smalti.sock`, 0600): one JSON request per connection from the
/// `smalti` CLI, answered with `{"ok":…}`. A bad request is refused without stopping the server. A socket file left
/// by a crashed instance is replaced; one a live instance answers on is never touched (`socketInUse`). Two instances
/// of the same build starting in the same instant could both see the file as stale; that window is accepted.
@MainActor
public final class UnixSocketTelemetry: TelemetrySource {
    private let path: String
    private let listener: SocketListener
    private let stream = AsyncStream<AgentEvent>.makeStream()

    public init(socketFile: URL, clock: @escaping @Sendable () -> Date) throws(IPCError) {
        path = socketFile.path(percentEncoded: false)
        let continuation = stream.continuation
        listener = try SocketListener(path: path) { line in
            Self.answer(line, clock: clock, deliver: { continuation.yield($0) })
        }
    }

    public func events() -> AsyncStream<AgentEvent> { stream.stream }

    /// Stops listening and removes the socket file.
    public func stop() {
        listener.stop()
        stream.continuation.finish()
    }

    nonisolated private static func answer(
        _ line: Data, clock: @Sendable () -> Date, deliver: (AgentEvent) -> Void
    ) -> IPCResponse {
        do {
            let request = try IPCCodec.decodeRequest(line)
            guard request.version == IPCLimits.version, request.kind == "event" else {
                return IPCResponse(ok: false, error: "unsupported request v\(request.version) \(request.kind)")
            }
            deliver(try HookPayloadTranslator.event(request, at: clock()))
            return IPCResponse(ok: true, error: nil)
        } catch {
            return IPCResponse(ok: false, error: String(describing: error))
        }
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
