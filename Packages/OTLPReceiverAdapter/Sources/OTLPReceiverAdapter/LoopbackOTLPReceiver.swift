import Darwin
import Foundation
import SmaltiCore
import Synchronization
import os

/// Smalti's OTLP/HTTP receiver (spec F7): a TCP socket bound to 127.0.0.1 only, on a port the system picks, that takes
/// `POST /v1/logs` with this run's bearer token and hands the decoded events to the main actor.
@MainActor
public final class LoopbackOTLPReceiver: TelemetryReceiver {
    public static let maximumConnections = 16

    private let decode: @Sendable (Data) throws -> [TelemetryEvent]
    private let idleTimeout: Duration
    private let maximumBody: Int
    private let token: @Sendable () -> String
    private var server: LoopbackServer?

    public init(
        decode: @escaping @Sendable (Data) throws -> [TelemetryEvent] = { body in try OTLPLogsDecoder.decode(body) },
        idleTimeout: Duration = .seconds(30),
        maximumBody: Int = 4 << 20, token: @escaping @Sendable () -> String = LoopbackOTLPReceiver.randomToken
    ) {
        self.decode = decode
        self.idleTimeout = idleTimeout
        self.maximumBody = maximumBody
        self.token = token
    }

    /// The address the socket is bound to, read back from the system (`getsockname`); nil while stopped.
    public var boundAddress: String? { server?.boundAddress }

    public func start(onBatch: @escaping @MainActor ([TelemetryEvent]) -> Void) throws(TelemetryReceiverError)
        -> TelemetryEndpoint
    {
        stop()
        let secret = token()
        let deliver: @Sendable ([TelemetryEvent]) -> Void = { events in
            Task { @MainActor in onBatch(events) }
        }
        let server = try LoopbackServer(
            settings: .init(
                token: secret, idleTimeout: idleTimeout, maximumBody: maximumBody,
                maximumConnections: Self.maximumConnections),
            decode: decode, deliver: deliver)
        self.server = server
        return TelemetryEndpoint(port: server.port, token: secret)
    }

    public func stop() {
        server?.stop()
        server = nil
    }

    /// 32 random bytes in hex, from the system's cryptographically secure generator.
    public nonisolated static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in
            let byte = UInt8.random(in: 0...255, using: &generator)
            return String(byte, radix: 16).count == 1 ? "0" + String(byte, radix: 16) : String(byte, radix: 16)
        }.joined()
    }
}

/// The socket and its connections, served on background queues; every mutable piece sits behind `state`.
private final class LoopbackServer: Sendable {
    struct Settings: Sendable {
        let token: String
        let idleTimeout: Duration
        let maximumBody: Int
        let maximumConnections: Int
    }

    private struct State {
        var connections: Set<Int32> = []
        var isStopped = false
    }

    let port: UInt16
    let boundAddress: String
    private let listener: Int32
    private let source: DispatchSourceRead
    private let settings: Settings
    private let decode: @Sendable (Data) throws -> [TelemetryEvent]
    private let deliver: @Sendable ([TelemetryEvent]) -> Void
    private let state = Mutex(State())
    private let closed = DispatchSemaphore(value: 0)
    private static let queue = DispatchQueue(label: "dev.simonriv.smalti.otlp")
    private static let connectionQueue = DispatchQueue(
        label: "dev.simonriv.smalti.otlp.connections", attributes: .concurrent)
    private static let log = Logger(subsystem: "dev.simonriv.smalti", category: "otlp")

    init(
        settings: Settings, decode: @escaping @Sendable (Data) throws -> [TelemetryEvent],
        deliver: @escaping @Sendable ([TelemetryEvent]) -> Void
    ) throws(TelemetryReceiverError) {
        self.settings = settings
        self.decode = decode
        self.deliver = deliver
        listener = try LoopbackSocket.listen(backlog: Int32(settings.maximumConnections))
        guard let bound = LoopbackSocket.boundAddress(of: listener) else {
            close(listener)
            throw .cannotListen(operation: "getsockname", errno: errno)
        }
        boundAddress = bound.address
        port = bound.port
        source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: Self.queue)
        let listening = listener
        let closed = self.closed
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.setCancelHandler {
            close(listening)
            closed.signal()
        }
        source.resume()
    }

    /// Stops listening, waits for the listening socket to close, and hangs up every open connection (each one's
    /// thread then closes its descriptor).
    func stop() {
        let open: Set<Int32>? = state.withLock { state in
            guard !state.isStopped else { return nil }
            state.isStopped = true
            return state.connections
        }
        guard let open else { return }
        source.cancel()
        _ = closed.wait(timeout: .now() + 1)
        open.forEach { shutdown($0, SHUT_RDWR) }
    }

    private func acceptOne() {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        let isAdmitted = state.withLock { state in
            guard !state.isStopped, state.connections.count < settings.maximumConnections else { return false }
            state.connections.insert(client)
            return true
        }
        guard isAdmitted else {
            close(client)
            return
        }
        Self.connectionQueue.async { [self] in serve(client) }
    }

    private func serve(_ client: Int32) {
        defer {
            state.withLock { _ = $0.connections.remove(client) }
            close(client)
        }
        LoopbackSocket.prepare(client, idleTimeout: settings.idleTimeout)
        var parser = HTTPRequestParser(maximumBody: settings.maximumBody)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return }
            for item in parser.feed(Data(buffer.prefix(count))) {
                guard handle(item, on: client) else { return }
            }
        }
    }

    /// Answers one parsed item; false when the connection must close.
    private func handle(_ item: ParsedItem, on client: Int32) -> Bool {
        switch item {
        case .request(let request):
            let answer = ReceiverRoute.respond(to: request, token: settings.token, decode: decode)
            if !answer.events.isEmpty { deliver(answer.events) }
            if answer.status != 200 { Self.log.debug("otlp request refused with \(answer.status)") }
            LoopbackSocket.write(ReceiverRoute.response(answer.status), to: client)
            return true
        case .failure(let status):
            LoopbackSocket.write(ReceiverRoute.response(status), to: client)
            return false
        }
    }
}

/// The BSD socket calls, kept in one place: bind to the loopback only and read the address back.
enum LoopbackSocket {
    static func listen(backlog: Int32) throws(TelemetryReceiverError) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .cannotListen(operation: "socket", errno: errno) }
        var on: Int32 = 1
        // Accepted connections inherit it: a client that hangs up never raises SIGPIPE in the app.
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
        // Safe: a sockaddr_in is laid out as the sockaddr it is passed as, with its exact size.
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw .cannotListen(operation: "bind", errno: code)
        }
        guard Darwin.listen(fd, backlog) == 0 else {
            let code = errno
            close(fd)
            throw .cannotListen(operation: "listen", errno: code)
        }
        return fd
    }

    static func boundAddress(of fd: Int32) -> (address: String, port: UInt16)? {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        // Safe: getsockname writes at most `length` bytes, the size of the sockaddr_in it is given.
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard result == 0, address.sin_family == sa_family_t(AF_INET) else { return nil }
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address.sin_addr, &text, socklen_t(text.count)) != nil else { return nil }
        return (
            String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
            UInt16(bigEndian: address.sin_port)
        )
    }

    static func prepare(_ client: Int32, idleTimeout: Duration) {
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let (seconds, attoseconds) = idleTimeout.components
        var timeout = timeval(tv_sec: Int(seconds), tv_usec: Int32(attoseconds / 1_000_000_000_000))
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    static func write(_ data: Data, to client: Int32) {
        // Safe: the buffer pointer is valid for the closure's duration and `count` bytes long.
        _ = data.withUnsafeBytes { Darwin.write(client, $0.baseAddress, data.count) }
    }
}
