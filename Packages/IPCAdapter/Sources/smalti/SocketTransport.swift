import Darwin
import Foundation

/// Sends one line over a Unix socket and waits briefly for the answer; any failure is `unreachable`.
struct SocketTransport: EventTransport, GuardTransport {
    /// F7.5: sends the line and reads the answer up to its newline, waiting at most `answerTimeout` for it.
    func exchange(_ line: Data, to socket: String, connectTimeout: Duration, answerTimeout: Duration)
        throws(TransportError) -> Data
    {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .unreachable("socket") }
        defer { close(fd) }
        setTimeout(fd, SO_SNDTIMEO, connectTimeout)
        setTimeout(fd, SO_RCVTIMEO, answerTimeout)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        guard connect(fd, to: socket) == 0 else { throw .unreachable(socket) }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, line.count) }
        guard written == line.count else { throw .unreachable(socket) }
        return readAnswer(fd)
    }

    private func setTimeout(_ fd: Int32, _ option: Int32, _ duration: Duration) {
        let parts = duration.components
        var value = timeval(tv_sec: Int(parts.seconds), tv_usec: Int32(parts.attoseconds / 1_000_000_000_000))
        setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Everything up to the first newline; whatever arrived when the peer closes or the timeout ends.
    private func readAnswer(_ fd: Int32) -> Data {
        var answer = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !answer.contains(UInt8(ascii: "\n")) {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            answer.append(contentsOf: buffer.prefix(count))
        }
        return answer
    }

    func send(_ line: Data, to socket: String, timeout: Duration) throws(TransportError) {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .unreachable("socket") }
        defer { close(fd) }
        let parts = timeout.components
        var seconds = timeval(tv_sec: Int(parts.seconds), tv_usec: Int32(parts.attoseconds / 1_000_000_000_000))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &seconds, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &seconds, socklen_t(MemoryLayout<timeval>.size))
        // An app that closes early must not kill the hook with SIGPIPE.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        guard connect(fd, to: socket) == 0 else { throw .unreachable(socket) }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, line.count) }
        guard written == line.count else { throw .unreachable(socket) }
        var answer = [UInt8](repeating: 0, count: 512)
        _ = read(fd, &answer, answer.count)
    }

    private func connect(_ fd: Int32, to path: String) -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            _ = path.utf8CString.withUnsafeBytes {
                buffer.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(buffer.count - 1)))
            }
        }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}
