import Foundation

/// A call's JSON as the timeline shows and copies it: compact, keys sorted by code point, non-ASCII as it is and only
/// `"`, `\` and control characters escaped (Python's `json.dumps(…, ensure_ascii=False, sort_keys=True,
/// separators=(",", ":"))`, the oracle's form). Foundation's `.sortedKeys` orders keys another way (review 1, M15).
enum CanonicalJSON {
    static func string(_ value: Any) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }

    private static func write(_ value: Any, into out: inout String) {
        switch value {
        case let object as [String: Any]:
            out += "{"
            for (index, key) in object.keys.sorted(by: {
                $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars)
            })
            .enumerated() {
                if index > 0 { out += "," }
                quote(key, into: &out)
                out += ":"
                write(object[key] ?? NSNull(), into: &out)
            }
            out += "}"
        case let array as [Any]:
            out += "["
            for (index, element) in array.enumerated() {
                if index > 0 { out += "," }
                write(element, into: &out)
            }
            out += "]"
        case let text as String: quote(text, into: &out)
        case let number as NSNumber: out += self.number(number)
        default: out += "null"
        }
    }

    private static func number(_ number: NSNumber) -> String {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
        guard CFNumberIsFloatType(number) else { return number.stringValue }
        let double = number.doubleValue
        return double == double.rounded() && abs(double) < 1e16 ? String(format: "%.1f", double) : "\(double)"
    }

    private static let shortEscapes: [Unicode.Scalar: String] = [
        "\"": "\\\"", "\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t", "\u{08}": "\\b", "\u{0C}": "\\f",
    ]

    private static func quote(_ text: String, into out: inout String) {
        out += "\""
        for scalar in text.unicodeScalars {
            if let escape = shortEscapes[scalar] {
                out += escape
            } else if scalar.value < 0x20 {
                out += String(format: "\\u%04x", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}
