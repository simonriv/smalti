import Foundation

public enum LayoutNameError: Error, Equatable, Sendable {
    case invalid(name: String, reason: String)
}

/// The name of a saved layout ("solen-dev"). It is also its file name, so it cannot hold path separators.
public struct LayoutName: Hashable, Sendable {
    public static let maximumLength = 60

    public let rawValue: String

    public init(_ raw: String) throws(LayoutNameError) {
        let name = raw.trimmingCharacters(in: .whitespaces)
        if let reason = Self.problem(with: name) { throw .invalid(name: raw, reason: reason) }
        rawValue = name
    }

    private static func problem(with name: String) -> String? {
        if name.isEmpty { return "empty" }
        if name.count > maximumLength { return "longer than \(maximumLength) characters" }
        if name.contains("/") || name.contains(":") { return "contains a path separator" }
        if name.hasPrefix(".") { return "starts with a dot" }
        return nil
    }
}
