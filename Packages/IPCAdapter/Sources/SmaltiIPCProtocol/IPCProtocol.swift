import Foundation

/// Fixed values of the wire format (spec F2, part C).
public enum IPCLimits {
    public static let version = 1
    /// A request larger than this is refused, whole.
    public static let maxMessageBytes = 1_048_576
}

/// One request per connection: a single JSON line,
/// `{"v":1,"kind":"event","pane":"<uuid>","hook":"Stop","payload":{…}}`. `payload` is the hook's own JSON, untouched.
public struct IPCRequest: Equatable, Sendable {
    public let version: Int
    public let kind: String
    public let pane: String
    public let hook: String
    public let payload: Data

    public init(pane: String, hook: String, payload: Data) {
        self.init(version: IPCLimits.version, kind: "event", pane: pane, hook: hook, payload: payload)
    }

    init(version: Int, kind: String, pane: String, hook: String, payload: Data) {
        self.version = version
        self.kind = kind
        self.pane = pane
        self.hook = hook
        self.payload = payload
    }
}

public struct IPCResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let error: String?

    public init(ok: Bool, error: String?) {
        self.ok = ok
        self.error = error
    }
}

public enum IPCCodecError: Error, Equatable, Sendable {
    case tooLarge(bytes: Int)
    case malformed(reason: String)
}

public enum IPCCodec {
    /// The request as one line ending in `\n`. A payload that is not a JSON object travels as `{}`.
    public static func encode(_ request: IPCRequest) throws(IPCCodecError) -> Data {
        let payload = (try? JSONSerialization.jsonObject(with: request.payload)) as? [String: Any] ?? [:]
        let object: [String: Any] = [
            "v": request.version, "kind": request.kind, "pane": request.pane, "hook": request.hook, "payload": payload,
        ]
        return try line(object)
    }

    public static func decodeRequest(_ line: Data) throws(IPCCodecError) -> IPCRequest {
        guard line.count <= IPCLimits.maxMessageBytes else { throw .tooLarge(bytes: line.count) }
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
            let version = object["v"] as? Int, let kind = object["kind"] as? String,
            let pane = object["pane"] as? String, let hook = object["hook"] as? String
        else { throw .malformed(reason: "not an IPC request") }
        let payload = (object["payload"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        return IPCRequest(
            version: version, kind: kind, pane: pane, hook: hook, payload: payload ?? Data("{}".utf8))
    }

    public static func encode(_ response: IPCResponse) throws(IPCCodecError) -> Data {
        do {
            return try JSONEncoder().encode(response) + Data([newline])
        } catch {
            throw .malformed(reason: String(describing: error))
        }
    }

    public static func decodeResponse(_ line: Data) throws(IPCCodecError) -> IPCResponse {
        do {
            return try JSONDecoder().decode(IPCResponse.self, from: line)
        } catch {
            throw .malformed(reason: String(describing: error))
        }
    }

    static let newline = UInt8(ascii: "\n")

    private static func line(_ object: [String: Any]) throws(IPCCodecError) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
                + Data([newline])
        } catch {
            throw .malformed(reason: String(describing: error))
        }
    }
}
