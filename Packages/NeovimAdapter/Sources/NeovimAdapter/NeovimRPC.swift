import Darwin
import Foundation
import SmaltiCore

/// One request to a Neovim over its `--listen` socket: `[0, id, method, params]`, answered by `[1, id, error,
/// result]`. Notifications that arrive in between are skipped. Blocking; callers run it off the main thread.
enum NeovimRPC {
    static let requestID: Int64 = 1

    static func call(socket path: String, method: String, params: [MsgPackValue], timeout: TimeInterval)
        throws(EditorError) -> MsgPackValue
    {
        let descriptor = try connect(path)
        defer { close(descriptor) }
        let request = MsgPack.encode(.array([.int(0), .int(requestID), .string(method), .array(params)]))
        try send(request, to: descriptor, socket: path)
        return try response(from: descriptor, socket: path, deadline: Date().addingTimeInterval(timeout))
    }

    private static func connect(_ path: String) throws(EditorError) -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw .unreachable(socket: path, reason: "socket: \(errno)") }
        var noSigPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor)
            throw .socketPathTooLong(path: path)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes + [0]) }
        // `sockaddr_un` is passed as the generic `sockaddr` connect expects, as the socket API requires.
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let reason = String(cString: strerror(errno))
            close(descriptor)
            throw .unreachable(socket: path, reason: reason)
        }
        return descriptor
    }

    private static func send(_ data: Data, to descriptor: Int32, socket path: String) throws(EditorError) {
        let written = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == data.count else { throw .unreachable(socket: path, reason: "write: \(errno)") }
    }

    private static func response(from descriptor: Int32, socket path: String, deadline: Date) throws(EditorError)
        -> MsgPackValue
    {
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            while let (message, count) = try? MsgPack.decode(received) {
                received.removeFirst(count)
                if let result = try answer(message, socket: path) { return result }
            }
            let remaining = Int32(deadline.timeIntervalSinceNow * 1000)
            guard remaining > 0 else { throw .unreachable(socket: path, reason: "timed out") }
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, remaining) > 0 else { throw .unreachable(socket: path, reason: "timed out") }
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { throw .unreachable(socket: path, reason: "closed") }
            received.append(contentsOf: buffer[0..<count])
        }
    }

    /// The result of our response; nil for anything else (a notification, another id).
    private static func answer(_ message: MsgPackValue, socket path: String) throws(EditorError) -> MsgPackValue? {
        guard case .array(let parts) = message, parts.count == 4, parts[0] == .int(1), parts[1] == .int(requestID)
        else { return nil }
        guard parts[2] == .nil else { throw .rejected(socket: path, reason: "\(parts[2])") }
        return parts[3]
    }
}
