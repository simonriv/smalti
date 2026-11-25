import Darwin
import Foundation
import SmaltiIPCProtocol

/// A minimal client for the tests: one request per connection, as the CLI does.
enum SocketClient {
    static func send(_ line: Data, to path: String) -> Data? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            _ = path.utf8CString.withUnsafeBytes {
                buffer.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(buffer.count - 1)))
            }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, line.count) }
        shutdown(fd, SHUT_WR)
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            response.append(contentsOf: buffer.prefix(count))
        }
        return response
    }

    /// Connects and writes `pieces` one by one, then reads the answer.
    static func send(pieces: [Data], to path: String) -> Data? {
        guard let fd = connected(path) else { return nil }
        defer { close(fd) }
        for piece in pieces {
            _ = piece.withUnsafeBytes { write(fd, $0.baseAddress, piece.count) }
            usleep(20_000)
        }
        shutdown(fd, SHUT_WR)
        return readAll(fd)
    }

    /// Writes `line` and keeps the connection open, as the `smalti` CLI does; the caller reads or closes.
    static func openWriting(_ line: Data, to path: String) -> Int32? {
        guard let fd = connected(path) else { return nil }
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, line.count) }
        return fd
    }

    /// Reads until the peer closes.
    static func readAll(from fd: Int32) -> Data {
        readAll(fd)
    }

    /// Connects and says nothing for `duration`.
    static func holdOpenSilently(_ path: String, for duration: Duration) {
        guard let fd = connected(path) else { return }
        usleep(
            useconds_t(duration.components.attoseconds / 1_000_000_000_000 + duration.components.seconds * 1_000_000))
        close(fd)
    }

    private static func connected(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            _ = path.utf8CString.withUnsafeBytes {
                buffer.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(buffer.count - 1)))
            }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    private static func readAll(_ fd: Int32) -> Data {
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            response.append(contentsOf: buffer.prefix(count))
        }
        return response
    }

    /// A socket file nobody listens on, as a crashed app leaves behind.
    static func leaveStaleSocket(at path: String) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            _ = path.utf8CString.withUnsafeBytes {
                buffer.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(buffer.count - 1)))
            }
        }
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        close(fd)
    }

    static func request(pane: String, hook: String, payload: String = "{}") -> Data {
        (try? IPCCodec.encode(IPCRequest(pane: pane, hook: hook, payload: Data(payload.utf8)))) ?? Data()
    }
}
