import Darwin
import Foundation
import SmaltiCore
import SmaltiIPCProtocol

/// `TelemetrySource` over a Unix socket (`<state>/smalti.sock`, 0600): one JSON request per connection from the
/// `smalti` CLI, answered with `{"ok":…}`. A bad request is refused without stopping the server. A socket file left
/// by a crashed instance is replaced; one a live instance answers on is never touched (`socketInUse`).
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
        unlink(path)
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
    private let source: DispatchSourceRead
    private let queue = DispatchQueue(label: "dev.simonriv.smalti.ipc")

    init(path: String, handle: @escaping @Sendable (Data) -> IPCResponse) throws(IPCError) {
        try Self.claim(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .socketFailed(operation: "socket", path: path, code: errno) }
        do {
            try Self.bind(fd, to: path)
        } catch {
            close(fd)
            throw error
        }
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let listening = fd
        source.setEventHandler { Self.serve(accept(listening, nil, nil), handle: handle) }
        source.setCancelHandler { close(listening) }
        source.resume()
    }

    func stop() {
        source.cancel()
    }

    /// Fails if a live instance answers on `path`; removes a stale file otherwise.
    private static func claim(_ path: String) throws(IPCError) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(probe) }
        var on: Int32 = 1
        setsockopt(probe, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        if connectTo(probe, path: path) == 0 { throw .socketInUse(path: path) }
        unlink(path)
    }

    private static func bind(_ fd: Int32, to path: String) throws(IPCError) {
        var address = socketAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw .socketFailed(operation: "bind", path: path, code: errno) }
        guard chmod(path, 0o600) == 0 else { throw .socketFailed(operation: "chmod", path: path, code: errno) }
        guard listen(fd, 16) == 0 else { throw .socketFailed(operation: "listen", path: path, code: errno) }
    }

    static func connectTo(_ fd: Int32, path: String) -> Int32 {
        var address = socketAddress(path)
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    private static func socketAddress(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            // Paths longer than sun_path are cut; Smalti's state paths are far shorter.
            _ = path.utf8CString.withUnsafeBytes {
                buffer.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(buffer.count - 1)))
            }
        }
        return address
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
