import Foundation

/// An `import` that a module boundary does not allow.
public struct ImportViolation: Equatable, Sendable, CustomStringConvertible {
    public let file: String
    public let line: Int
    public let module: String

    public init(file: String, line: Int, module: String) {
        self.file = file
        self.line = line
        self.module = module
    }

    public var description: String { "\(file):\(line) imports \(module)" }
}

/// Finds the imports that break a module boundary. Shared by every import guard so they agree on what an
/// import looks like (attributes such as `@preconcurrency`, declaration kinds such as `import struct`).
public struct ImportScanner: Sendable {
    private let isForbidden: @Sendable (String) -> Bool

    private init(isForbidden: @escaping @Sendable (String) -> Bool) {
        self.isForbidden = isForbidden
    }

    /// Flags every module except `modules`.
    public static func allowing(_ modules: Set<String>) -> ImportScanner {
        ImportScanner { !modules.contains($0) }
    }

    /// Flags only `modules`.
    public static func forbidding(_ modules: Set<String>) -> ImportScanner {
        ImportScanner { modules.contains($0) }
    }

    public func violations(in source: String, file: String) -> [ImportViolation] {
        let pattern = Self.importPattern()
        return
            source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, line in
                guard let match = line.firstMatch(of: pattern) else { return nil }
                let module = String(match.1)
                guard isForbidden(module) else { return nil }
                return ImportViolation(file: file, line: index + 1, module: module)
            }
    }

    /// Scans every `.swift` file under `directory`.
    public func violations(inDirectory directory: URL) throws -> [ImportViolation] {
        try Self.swiftFiles(in: directory).flatMap { url in
            violations(in: try String(contentsOf: url, encoding: .utf8), file: url.path(percentEncoded: false))
        }
    }

    /// Every `.swift` file under `directory`, recursively.
    public static func swiftFiles(in directory: URL) -> [URL] {
        FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
    }

    private static func importPattern() -> Regex<(Substring, Substring)> {
        /^\s*(?:@\w+\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(\w+)/
    }
}
