import Foundation
import SmaltiCore

/// One HTTP/1.1 request as the receiver needs it: header names in lower case, the body by `Content-Length`.
struct HTTPRequest: Equatable, Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

/// What the parser got out of the bytes so far: a whole request, or a failure after which the connection must close
/// (its framing is lost).
enum ParsedItem: Equatable, Sendable {
    case request(HTTPRequest)
    case failure(status: Int)
}

/// Splits a connection's bytes into requests, however the reads cut them. Only `Content-Length` framing: chunked
/// bodies are refused (411), as is a POST without a length.
struct HTTPRequestParser {
    static let maximumHeadBytes = 16 * 1024
    private static let headEnd = Data("\r\n\r\n".utf8)

    private let maximumBody: Int
    private var buffer = Data()
    private var hasFailed = false

    init(maximumBody: Int) {
        self.maximumBody = maximumBody
    }

    /// Bytes of a request that has not arrived whole yet.
    var hasPartialRequest: Bool { !buffer.isEmpty }

    mutating func feed(_ data: Data) -> [ParsedItem] {
        guard !hasFailed else { return [] }
        buffer.append(data)
        var items: [ParsedItem] = []
        while let item = next() {
            items.append(item)
            if case .failure = item {
                hasFailed = true
                break
            }
        }
        return items
    }

    private mutating func next() -> ParsedItem? {
        guard let end = buffer.range(of: Self.headEnd) else {
            return buffer.count > Self.maximumHeadBytes ? .failure(status: 400) : nil
        }
        let head = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
        let parsed: (method: String, path: String, headers: [String: String], length: Int)
        switch Self.parseHead(head, maximumBody: maximumBody) {
        case .success(let value): parsed = value
        case .failure(let status): return .failure(status: status.code)
        }
        guard buffer.distance(from: end.upperBound, to: buffer.endIndex) >= parsed.length else { return nil }
        let bodyEnd = buffer.index(end.upperBound, offsetBy: parsed.length)
        let request = HTTPRequest(
            method: parsed.method, path: parsed.path, headers: parsed.headers,
            body: Data(buffer[end.upperBound..<bodyEnd]))
        buffer = Data(buffer[bodyEnd...])
        return .request(request)
    }

    struct Status: Error {
        let code: Int
    }

    private static func parseHead(_ head: String, maximumBody: Int)
        -> Result<(method: String, path: String, headers: [String: String], length: Int), Status>
    {
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1."), requestLine[1].hasPrefix("/") else {
            return .failure(Status(code: 400))
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .failure(Status(code: 400)) }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let method = String(requestLine[0])
        if headers["transfer-encoding"] != nil { return .failure(Status(code: 411)) }
        guard let lengthText = headers["content-length"] else {
            return method == "POST"
                ? .failure(Status(code: 411)) : .success((method, String(requestLine[1]), headers, 0))
        }
        guard let length = Int(lengthText), length >= 0 else { return .failure(Status(code: 400)) }
        guard length <= maximumBody else { return .failure(Status(code: 413)) }
        return .success((method, String(requestLine[1]), headers, length))
    }
}

/// What the receiver answers each request (spec F7): the token first, then the route, the method, the encoding and
/// the body.
enum ReceiverRoute {
    static let logsPath = "/v1/logs"

    static func respond(
        to request: HTTPRequest, token: String, decode: (Data) throws -> [TelemetryEvent]
    ) -> (status: Int, events: [TelemetryEvent]) {
        guard isAuthorized(request.headers["authorization"], token: token) else { return (401, []) }
        guard request.path == logsPath else { return (404, []) }
        guard request.method == "POST" else { return (405, []) }
        if let encoding = request.headers["content-encoding"], encoding.lowercased() != "identity" { return (415, []) }
        guard let events = try? decode(request.body) else { return (400, []) }
        return (200, events)
    }

    /// Compares every byte whatever the first difference, so the time taken does not tell how much matched.
    private static func isAuthorized(_ header: String?, token: String) -> Bool {
        let expected = Array("Bearer \(token)".utf8)
        let given = Array((header ?? "").utf8)
        guard given.count == expected.count else { return false }
        return zip(given, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 411: "Length Required"
        case 413: "Content Too Large"
        case 415: "Unsupported Media Type"
        default: "Error"
        }
    }

    static func response(_ status: Int) -> Data {
        let body = "{}"
        return Data(
            "HTTP/1.1 \(status) \(reason(status))\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
                .utf8)
    }
}
