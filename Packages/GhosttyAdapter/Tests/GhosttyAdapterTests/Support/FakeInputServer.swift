import Darwin
import Foundation

/// The Smalti side of the input socket for zsh tests: accepts one shell and answers each line as `mode` says.
final class FakeInputServer: @unchecked Sendable {
    enum Mode: Sendable {
        /// Answers through `reply` (fields of the received line → answer lines).
        case normal
        /// Answers 2 s late.
        case slow
        /// Accepts and never reads: the socket buffer fills.
        case neverReads
        /// Closes the connection after this many lines.
        case closesAfter(Int)
        /// Answers every line with a `seq` one behind.
        case staleSeq
    }

    let path = "/tmp/smalti-zsh-\(UUID().uuidString.prefix(8)).sock"
    private let mode: Mode
    private let reply: @Sendable ([String]) -> [String]
    private let lock = NSLock()
    private var lines: [String] = []
    private let listening: Int32
    private var client: Int32 = -1

    init(mode: Mode = .normal, reply: @escaping @Sendable ([String]) -> [String] = { _ in [] }) throws {
        self.mode = mode
        self.reply = reply
        listening = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            _ = path.utf8CString.withUnsafeBytes {
                buffer.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(buffer.count - 1)))
            }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listening, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listening, 4) == 0 else { throw POSIXError(.EADDRINUSE) }
        Thread { [self] in serve() }.start()
    }

    deinit { stop() }

    var received: [String] { lock.withLock { lines } }

    func stop() {
        lock.withLock {
            if client >= 0 { close(client) }
            client = -1
        }
        close(listening)
        unlink(path)
    }

    private func serve() {
        let accepted = accept(listening, nil, nil)
        guard accepted >= 0 else { return }
        var on: Int32 = 1
        setsockopt(accepted, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        lock.withLock { client = accepted }
        if case .neverReads = mode { return }
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(accepted, &buffer, buffer.count)
            guard count > 0 else { return }
            pending.append(contentsOf: buffer.prefix(count))
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...newline)
                guard handle(line, on: accepted) else { return }
            }
        }
    }

    /// False once the connection was closed on purpose.
    private func handle(_ line: String, on fd: Int32) -> Bool {
        let count = lock.withLock { () -> Int in
            lines.append(line)
            return lines.count
        }
        if case .closesAfter(let limit) = mode, count >= limit {
            lock.withLock {
                close(fd)
                client = -1
            }
            return false
        }
        var fields = line.components(separatedBy: "\t")
        if case .staleSeq = mode, fields.count > 1, let seq = Int(fields[1]) { fields[1] = String(seq - 1) }
        let answers = reply(fields)
        if case .slow = mode, !answers.isEmpty { Thread.sleep(forTimeInterval: 2) }
        // "RAW:" answers go out verbatim, without the newline (a partial answer).
        for answer in answers { send(answer.hasPrefix("RAW:") ? String(answer.dropFirst(4)) : answer + "\n", to: fd) }
        return true
    }

    /// F5: a message Smalti sends without being asked (the spontaneous `prompt`, a new `promptstyle`).
    func push(_ line: String) {
        let fd = lock.withLock { client }
        guard fd >= 0 else { return }
        send(line + "\n", to: fd)
    }

    private func send(_ text: String, to fd: Int32) {
        let data = Data(text.utf8)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
    }

    func waitFor(_ predicate: ([String]) -> Bool, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(received) { return true }
            usleep(10_000)
        }
        return predicate(received)
    }
}
