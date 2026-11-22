import Foundation

/// SmaltiCore stays pure Swift: Foundation value types are the only allowed import.
private let allowedModules: Set<String> = ["Foundation"]

private func importPattern() -> Regex<(Substring, Substring)> {
    /^\s*(?:@\w+\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(\w+)/
}

struct ImportViolation: Equatable, CustomStringConvertible {
    let file: String
    let line: Int
    let module: String

    var description: String { "\(file):\(line) imports \(module)" }
}

func forbiddenImports(in source: String, file: String) -> [ImportViolation] {
    let pattern = importPattern()
    return
        source
        .split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
        .compactMap { index, line in
            guard let match = line.firstMatch(of: pattern) else { return nil }
            let module = String(match.1)
            guard !allowedModules.contains(module) else { return nil }
            return ImportViolation(file: file, line: index + 1, module: module)
        }
}

func forbiddenImports(inDirectory directory: URL) throws -> [ImportViolation] {
    let files =
        FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" } ?? []
    return try files.flatMap { url in
        forbiddenImports(in: try String(contentsOf: url, encoding: .utf8), file: url.path(percentEncoded: false))
    }
}
