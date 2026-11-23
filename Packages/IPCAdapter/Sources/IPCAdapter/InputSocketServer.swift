import Darwin
import Foundation
import SmaltiCore
import Synchronization

/// One shell's connection to the input socket. The app answers through `send`, which never blocks and writes a
/// message whole or not at all: a shell that stops reading loses answers instead of stalling Smalti, and never
/// receives half a line. Once the shell is gone, `send` does nothing (the descriptor is never reused by mistake).
public struct InputConnection: Hashable, Sendable {
    /// Answers are refused above this size (see `InputProtocol.maximumAnswerBytes`).
    public static let maximumMessageBytes = InputProtocol.maximumAnswerBytes

    public let id: UUID
    let writer: ConnectionWriter

    init(writer: ConnectionWriter) {
        id = UUID()
        self.writer = writer
    }

    /// True when the whole message was written; false when it was too big, did not fit or the shell is gone.
    @discardableResult
    public func send(_ message: SmaltiMessage) -> Bool {
        let data = Data((InputProtocol.encode(message) + "\n").utf8)
        guard data.count <= Self.maximumMessageBytes else { return false }
        return writer.write(data)
    }

    /// Ends the connection from the app's side (its pane closed, or a newer shell took the pane): the reader sees
    /// the end and reports it once through `onClose`.
    public func close() {
        writer.shutDown()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// F4's shell input channel (`<state>/input.sock`, 0600): every zsh of every pane keeps one connection open and
/// sends one `ShellPacket` (a message and its directory) per line. Each connection is read on its own thread, never the main one, so the socket
/// always drains and a shell is never left blocked writing. Unreadable lines are dropped; a line over
/// `maximumLineBytes` is skipped up to its newline.
public final class InputSocketServer: Sendable {
    public static let maximumLineBytes = 64 * 1024

    private let listener: InputListener
    private let closeHandler = Guarded<(@Sendable (InputConnection) -> Void)?>(nil)

    /// Called once when a connection ends (the shell exited or closed it).
    public var onClose: (@Sendable (InputConnection) -> Void)? {
        get { closeHandler.value }
        set { closeHandler.value = newValue }
    }

    public init(socketFile: URL, handler: @escaping @Sendable (InputConnection, ShellPacket) -> Void) throws(IPCError) {
        let closeHandler = closeHandler
        listener = try InputListener(path: socketFile.path(percentEncoded: false)) { event in
            switch event {
            case .message(let connection, let message): handler(connection, message)
            case .closed(let connection): closeHandler.value?(connection)
            }
        }
    }

    public func stop() {
        listener.stop()
    }

    /// The listening socket and every open client, for the tests.
    var openDescriptors: [Int32] { listener.openDescriptors }
}

enum InputEvent {
    case message(InputConnection, ShellPacket)
    case closed(InputConnection)
}

/// Owns one client's descriptor. Every use (write, shutdown, close) happens under the same lock, so nothing is
/// ever written to a descriptor number after it was closed and handed to someone else (another pane's terminal).
/// The socket is `O_NONBLOCK` and `SO_NOSIGPIPE`; a message only goes out when the send buffer has room for all
/// of it, and a short write (should the kernel still cut it) shuts the connection, since the shell would read a
/// broken line.
final class ConnectionWriter: Sendable {
    private let descriptor: Mutex<Int32?>

    init(fd: Int32) {
        descriptor = Mutex(fd)
    }

    var fd: Int32? { descriptor.withLock { $0 } }

    func write(_ data: Data) -> Bool {
        descriptor.withLock { slot in
            guard let fd = slot, Self.room(in: fd) >= data.count else { return false }
            let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, data.count) }
            if written == data.count { return true }
            if written > 0 { shutdown(fd, SHUT_RDWR) }
            return false
        }
    }

    /// Wakes the reader: it sees the end of the stream and finishes the connection.
    func shutDown() {
        descriptor.withLock { slot in
            if let fd = slot { shutdown(fd, SHUT_RDWR) }
        }
    }

    func close() {
        descriptor.withLock { slot in
            if let fd = slot { Darwin.close(fd) }
            slot = nil
        }
    }

    /// Free bytes in the socket's send buffer (`SO_SNDBUF` minus the bytes still queued, `SO_NWRITE`).
    private static func room(in fd: Int32) -> Int {
        var size: Int32 = 0
        var queued: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, &length) == 0 else { return 0 }
        length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_NWRITE, &queued, &length) == 0 else { return 0 }
        return Int(size - queued)
    }
}

/// Accepts on a background queue and reads each connection on a thread of its own. Every descriptor is
/// close-on-exec, so none leaks into the shells, generators or other processes Smalti starts.
private final class InputListener: Sendable {
    private let fd: Int32
    private let path: String
    private let source: DispatchSourceRead
    private let stopped: Guarded<Bool>
    private let clients = Guarded<[ConnectionWriter]>([])

    init(path: String, deliver: @escaping @Sendable (InputEvent) -> Void) throws(IPCError) {
        try UnixSocketFile.checkLength(path)
        try UnixSocketFile.claim(path)
        self.path = path
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .socketFailed(operation: "socket", path: path, code: errno) }
        Self.prepare(fd)
        do {
            try UnixSocketFile.bind(fd, to: path)
        } catch {
            close(fd)
            unlink(path)
            throw error
        }
        let stopped = Guarded(false)
        self.stopped = stopped
        source = DispatchSource.makeReadSource(
            fileDescriptor: fd, queue: DispatchQueue(label: "dev.simonriv.smalti.input"))
        let listening = fd
        let clients = clients
        source.setEventHandler {
            let client = accept(listening, nil, nil)
            guard client >= 0 else { return }
            Self.prepare(client)
            let writer = ConnectionWriter(fd: client)
            // A connection that arrives while stopping is turned away at once.
            guard !stopped.value else {
                writer.close()
                return
            }
            clients.update { $0.append(writer) }
            let thread = Thread {
                LineReader(writer: writer).serve(deliver: deliver)
                clients.update { $0.removeAll { $0 === writer } }
                writer.close()
            }
            thread.name = "dev.simonriv.smalti.input.client"
            thread.start()
        }
        source.setCancelHandler { close(listening) }
        source.resume()
    }

    deinit {
        stop()
    }

    /// The listening socket and every open client, for the tests.
    var openDescriptors: [Int32] { [fd] + clients.value.compactMap(\.fd) }

    /// Stops listening, wakes every reader (their connections end) and removes the socket file, once.
    func stop() {
        var wasStopped = false
        stopped.update { done in
            wasStopped = done
            done = true
        }
        guard !wasStopped else { return }
        source.cancel()
        clients.value.forEach { $0.shutDown() }
        unlink(path)
    }

    /// Close-on-exec, non-blocking and without SIGPIPE.
    private static func prepare(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }
}

/// Reads newline-terminated messages from one client until it hangs up or says `bye`. The socket is non-blocking,
/// so the reader waits in `poll`. A line longer than `maximumLineBytes` is dropped whole.
private struct LineReader {
    let writer: ConnectionWriter

    func serve(deliver: (InputEvent) -> Void) {
        guard let fd = writer.fd else { return }
        let connection = InputConnection(writer: writer)
        var pending = Data()
        var isSkipping = false
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            var waiting = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&waiting, 1, -1) >= 0 || errno == EINTR else { break }
            let count = read(fd, &buffer, buffer.count)
            if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            guard count > 0 else { break }
            pending.append(contentsOf: buffer.prefix(count))
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                if isSkipping || line.count > InputSocketServer.maximumLineBytes {
                    isSkipping = false
                } else if let message = try? InputProtocol.decode(String(decoding: line, as: UTF8.self)) {
                    deliver(.message(connection, message))
                    // The shell is leaving; a background child may still hold its socket open.
                    if message.message == .bye {
                        deliver(.closed(connection))
                        return
                    }
                }
            }
            if pending.count > InputSocketServer.maximumLineBytes {
                pending.removeAll()
                isSkipping = true
            }
        }
        deliver(.closed(connection))
    }
}

/// A value shared between threads, every access under a lock (`Mutex` itself cannot be captured by closures).
final class Guarded<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    init(_ value: Value) {
        storage = Mutex(value)
    }

    var value: Value {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    func update(_ change: (inout Value) -> Void) {
        storage.withLock { change(&$0) }
    }
}
