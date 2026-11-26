import Foundation

/// Why a JSONL file could not be read.
public enum JSONLReadError: Error, Equatable, Sendable {
    case missing(path: String)
    case unreadable(path: String, reason: String)

    static func reading(_ file: URL, _ error: any Error) -> JSONLReadError {
        let path = file.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return .missing(path: path) }
        return .unreadable(path: path, reason: String(describing: error))
    }
}
