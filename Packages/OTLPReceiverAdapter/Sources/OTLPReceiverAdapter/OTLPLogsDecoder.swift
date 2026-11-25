import Foundation
import SmaltiCore

public enum OTLPDecodeError: Error, Equatable, Sendable {
    case notJSON(reason: String)
    /// JSON without `resourceLogs`: another signal or another program.
    case notLogsRequest
}

/// Reads an OTLP/HTTP JSON `ExportLogsServiceRequest` and keeps Claude Code's `api_request` and `api_error` events
/// (spec F7). A record of another event, without `session.id` or with a field that cannot be read is skipped; the rest
/// of the batch still counts.
public enum OTLPLogsDecoder {
    private static let prefix = "claude_code."

    public static func decode(_ body: Data) throws(OTLPDecodeError) -> [TelemetryEvent] {
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: body) } catch {
            throw .notJSON(reason: error.localizedDescription)
        }
        guard let object = root as? [String: Any], let resources = object["resourceLogs"] as? [[String: Any]] else {
            throw .notLogsRequest
        }
        return resources.flatMap { ($0["scopeLogs"] as? [[String: Any]]) ?? [] }
            .flatMap { ($0["logRecords"] as? [[String: Any]]) ?? [] }
            .compactMap(event)
    }

    private static func event(_ record: [String: Any]) -> TelemetryEvent? {
        let attributes = OTLPAttributes(record["attributes"] as? [[String: Any]] ?? [])
        guard let name = name(record, attributes), let sessionID = attributes.string("session.id"),
            let at = timestamp(record, attributes), let sequence = attributes.optionalInt("event.sequence"),
            let model = attributes.optionalString("model")
        else { return nil }
        switch name {
        case "api_request":
            guard let duration = attributes.int("duration_ms"), duration >= 0, let cost = cost(attributes), cost >= 0
            else { return nil }
            return .apiRequest(
                APIRequest(
                    sessionID: sessionID, sequence: sequence.value, at: at, model: model.value,
                    durationMilliseconds: duration, costMicroUSD: cost))
        case "api_error":
            // An unreadable status still counts the failure, without its code.
            return .apiError(
                APIError(
                    sessionID: sessionID, sequence: sequence.value, at: at, model: model.value,
                    statusCode: attributes.int("status_code")))
        default:
            return nil
        }
    }

    private static func name(_ record: [String: Any], _ attributes: OTLPAttributes) -> String? {
        if let name = attributes.string("event.name") {
            return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
        }
        guard let body = (record["body"] as? [String: Any])?["stringValue"] as? String, body.hasPrefix(prefix) else {
            return nil
        }
        return String(body.dropFirst(prefix.count))
    }

    /// `event.timestamp` (ISO 8601), else the record's `timeUnixNano`.
    private static func timestamp(_ record: [String: Any], _ attributes: OTLPAttributes) -> Date? {
        if let date = attributes.string("event.timestamp").flatMap(ISO8601.date) { return date }
        guard let nanos = OTLPAttributes.integer(record["timeUnixNano"]) else { return nil }
        return Date(timeIntervalSince1970: Double(nanos) / 1_000_000_000)
    }

    /// `cost_usd_micros` when present, else `cost_usd` × 10⁶; 0 when neither is sent, nil when one is unreadable.
    private static func cost(_ attributes: OTLPAttributes) -> Int? {
        if attributes.has("cost_usd_micros") { return attributes.int("cost_usd_micros") }
        guard attributes.has("cost_usd") else { return 0 }
        return attributes.double("cost_usd").flatMap { OTLPAttributes.exactInt($0 * 1_000_000) }
    }
}

/// The `key`/`value` pairs of an OTLP record. Numbers may come as `intValue` (a JSON number or, for 64-bit values, a
/// string), `doubleValue`, or a numeric `stringValue`.
private struct OTLPAttributes {
    /// An optional field: absent is `.some(nil)`, present but unreadable is `nil`.
    struct Optional<Value> {
        let value: Value?
    }

    private let values: [String: [String: Any]]

    init(_ list: [[String: Any]]) {
        var values: [String: [String: Any]] = [:]
        for item in list {
            if let key = item["key"] as? String, let value = item["value"] as? [String: Any] { values[key] = value }
        }
        self.values = values
    }

    func has(_ key: String) -> Bool { values[key] != nil }

    func string(_ key: String) -> String? { values[key]?["stringValue"] as? String }

    func optionalString(_ key: String) -> Optional<String>? {
        guard has(key) else { return Optional(value: nil) }
        return string(key).map { Optional(value: $0) }
    }

    func int(_ key: String) -> Int? {
        guard let value = values[key] else { return nil }
        if let integer = Self.integer(value["intValue"]) { return integer }
        if let double = value["doubleValue"] as? Double { return Self.exactInt(double) }
        return (value["stringValue"] as? String).flatMap { Int($0) }
    }

    func optionalInt(_ key: String) -> Optional<Int>? {
        guard has(key) else { return Optional(value: nil) }
        return int(key).map { Optional(value: $0) }
    }

    func double(_ key: String) -> Double? {
        guard let value = values[key] else { return nil }
        if let double = value["doubleValue"] as? Double, double.isFinite { return double }
        if let integer = Self.integer(value["intValue"]) { return Double(integer) }
        return (value["stringValue"] as? String).flatMap { Double($0) }
    }

    /// The rounded value when it fits in an `Int`; nil for NaN, infinities and anything out of range.
    static func exactInt(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(exactly: value.rounded())
    }

    static func integer(_ raw: Any?) -> Int? {
        if let text = raw as? String { return Int(text) }
        guard let number = raw as? NSNumber, CFNumberIsFloatType(number) == false else { return nil }
        return number.intValue
    }
}

private enum ISO8601 {
    // Safe to share across threads: Foundation's date formatters are thread-safe once configured, and these are
    // never changed after creation. Reused because building one per record is costly.
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let whole = ISO8601DateFormatter()

    static func date(_ text: String) -> Date? {
        fractional.date(from: text) ?? whole.date(from: text)
    }
}
