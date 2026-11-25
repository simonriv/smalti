import Darwin
import Foundation

/// A blocking HTTP/1.1 client for the receiver's tests: raw bytes out, status and body back.
final class TestHTTPClient {
    struct Response: Equatable {
        let status: Int
        let body: String
    }

    let fd: Int32
    private var pending = Data()
    /// The `errno` of the last connection that failed, read before anything else can change it.
    nonisolated(unsafe) static var lastConnectError: Int32 = 0

    /// Connects to `address` (an IPv4 or IPv6 literal); `nil` with `errno` set when the connection is refused.
    init?(address: String = "127.0.0.1", port: UInt16, timeoutSeconds: Int = 2) {
        let isIPv6 = address.contains(":")
        fd = socket(isIPv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let connected = isIPv6 ? Self.connect6(fd, address, port) : Self.connect4(fd, address, port)
        guard connected else {
            Self.lastConnectError = errno
            close(fd)
            return nil
        }
    }

    deinit { close(fd) }

    private static func connect4(_ fd: Int32, _ address: String, _ port: UInt16) -> Bool {
        var socketAddress = sockaddr_in()
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = port.bigEndian
        inet_pton(AF_INET, address, &socketAddress.sin_addr)
        // Safe: a sockaddr_in is laid out as the sockaddr it is passed as, with its exact size.
        return withUnsafePointer(to: &socketAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private static func connect6(_ fd: Int32, _ address: String, _ port: UInt16) -> Bool {
        var socketAddress = sockaddr_in6()
        socketAddress.sin6_family = sa_family_t(AF_INET6)
        socketAddress.sin6_port = port.bigEndian
        inet_pton(AF_INET6, address, &socketAddress.sin6_addr)
        // Safe: as above, for sockaddr_in6.
        return withUnsafePointer(to: &socketAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
            }
        }
    }

    func send(_ text: String) { send(Data(text.utf8)) }

    func send(_ data: Data) {
        // Safe: the buffer pointer is valid for the closure's duration and `count` bytes long.
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
    }

    /// Reads one response (status line, headers, `Content-Length` body); nil on timeout or close.
    func response() -> Response? {
        while true {
            if let parsed = Self.parse(&pending) { return parsed }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else { return nil }
            pending.append(contentsOf: chunk.prefix(count))
        }
    }

    /// True when the server closed the connection (read returns 0) within the timeout.
    func isClosedByServer() -> Bool {
        var byte: UInt8 = 0
        return read(fd, &byte, 1) == 0
    }

    private static func parse(_ buffer: inout Data) -> Response? {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let status = Int(lines[0].split(separator: " ")[1]) ?? 0
        let length =
            lines.dropFirst().first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        guard buffer.distance(from: end.upperBound, to: buffer.endIndex) >= length else { return nil }
        let bodyEnd = buffer.index(end.upperBound, offsetBy: length)
        let body = String(decoding: buffer[end.upperBound..<bodyEnd], as: UTF8.self)
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return Response(status: status, body: body)
    }

    static func post(path: String = "/v1/logs", body: String, token: String?, extraHeaders: [String] = []) -> String {
        var headers = ["POST \(path) HTTP/1.1", "Host: 127.0.0.1", "Content-Type: application/json"]
        if let token { headers.append("Authorization: Bearer \(token)") }
        headers += extraHeaders
        headers.append("Content-Length: \(body.utf8.count)")
        return headers.joined(separator: "\r\n") + "\r\n\r\n" + body
    }
}

/// The machine's first IPv4 address that is not the loopback, if any.
func lanAddress() -> String? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
        guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET) else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        if !text.hasPrefix("127.") { return text }
    }
    return nil
}
