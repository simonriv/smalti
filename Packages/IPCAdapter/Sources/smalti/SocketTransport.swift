import Darwin
import Foundation

/// Sends one line over a Unix socket and waits briefly for the answer; any failure is `unreachable`.
struct SocketTransport: EventTransport {
    func send(_ line: Data, to socket: String, timeout: Duration) throws(TransportError) {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .unreachable("socket") }
        defer { close(fd) }
        var seconds = timeval(tv_sec: 0, tv_usec: Int32(timeout.components.attoseconds / 1_000_000_000_000))
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
