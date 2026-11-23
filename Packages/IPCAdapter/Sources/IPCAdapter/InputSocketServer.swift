import Darwin
import Foundation
import SmaltiCore
import Synchronization

/// One shell's connection to the input socket. The app answers through `send`, which never blocks: a shell that
/// stops reading loses answers instead of stalling Smalti (zsh only cares about the latest one anyway).
public struct InputConnection: Hashable, Sendable {
    public let id: UUID
    private let writer: ConnectionWriter

    init(writer: ConnectionWriter) {
        id = UUID()
        self.writer = writer
    }

    public func send(_ message: SmaltiMessage) {
        writer.write(Data((InputProtocol.encode(message) + "\n").utf8))
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// F4's shell input channel (`<state>/input.sock`, 0600): every zsh of every pane keeps one connection open and
/// sends one `ShellMessage` per line. Each connection is read on its own thread, never the main one, so the socket
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

    public init(socketFile: URL, handler: @escaping @Sendable (InputConnection, ShellMessage) -> Void) throws(IPCError)
    {
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
}

enum InputEvent {
    case message(InputConnection, ShellMessage)
    case closed(InputConnection)
}

/// Writes answers to one client without blocking (the socket is `O_NONBLOCK`; `MSG_DONTWAIT` alone still blocks
/// on Darwin's Unix sockets): a full buffer or a closed peer drops the answer. The socket has `SO_NOSIGPIPE`, so a
/// closed peer never raises SIGPIPE.
final class ConnectionWriter: Sendable {
    private let fd: Int32

    init(fd: Int32) {
        self.fd = fd
    }

    func write(_ data: Data) {
        _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, data.count) }
    }
}

/// Accepts on a background queue and reads each connection on a thread of its own.
private final class InputListener: Sendable {
    private let fd: Int32
    private let path: String
    private let source: DispatchSourceRead
    private let stopped = Mutex(false)
    private let clients = Guarded<[Int32]>([])

    init(path: String, deliver: @escaping @Sendable (InputEvent) -> Void) throws(IPCError) {
        try UnixSocketFile.checkLength(path)
        try UnixSocketFile.claim(path)
        self.path = path
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .socketFailed(operation: "socket", path: path, code: errno) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        do {
            try UnixSocketFile.bind(fd, to: path)
        } catch {
            close(fd)
            unlink(path)
            throw error
        }
        source = DispatchSource.makeReadSource(
            fileDescriptor: fd, queue: DispatchQueue(label: "dev.simonriv.smalti.input"))
        let listening = fd
        let clients = clients
        source.setEventHandler {
            let client = accept(listening, nil, nil)
            guard client >= 0 else { return }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) | O_NONBLOCK)
            clients.update { $0.append(client) }
            let thread = Thread {
                LineReader(fd: client).serve(deliver: deliver)
                clients.update { $0.removeAll { $0 == client } }
                close(client)
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

    /// Stops listening, wakes every reader (their connections end) and removes the socket file, once.
    func stop() {
        let wasStopped = stopped.withLock { done in
            defer { done = true }
            return done
        }
        guard !wasStopped else { return }
        source.cancel()
        clients.value.forEach { shutdown($0, SHUT_RDWR) }
        unlink(path)
    }
}

/// Reads newline-terminated messages from one client until it hangs up. The socket is non-blocking, so the reader
/// waits in `poll`. A line longer than `maximumLineBytes` is dropped whole.
private struct LineReader {
    let fd: Int32

    func serve(deliver: (InputEvent) -> Void) {
        let connection = InputConnection(writer: ConnectionWriter(fd: fd))
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
