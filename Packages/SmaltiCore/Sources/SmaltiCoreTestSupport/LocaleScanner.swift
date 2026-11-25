import Foundation

/// F7.7: SmaltiCore never asks the system for the language; it receives `InterfaceLanguage`.
public enum LocaleScanner {
    public struct Violation: Equatable, Sendable, CustomStringConvertible {
        public let file: String
        public let line: Int
        public let text: String
        public var description: String { "\(file):\(line) reads the system language: \(text)" }
    }

    private static let forbidden = [
        "Locale.", "Bundle.", "String(localized", "NSLocalizedString", "LocalizedStringResource",
    ]

    public static func violations(in source: String, file: String) -> [Violation] {
        source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            let code = line.trimmingCharacters(in: .whitespaces)
            guard !code.hasPrefix("//"), forbidden.contains(where: { code.contains($0) }) else { return nil }
            return Violation(file: file, line: index + 1, text: code)
        }
    }

    public static func violations(inDirectory directory: URL) throws -> [Violation] {
        try ImportScanner.swiftFiles(in: directory).flatMap { url in
            violations(in: try String(contentsOf: url, encoding: .utf8), file: url.lastPathComponent)
        }
    }
}
