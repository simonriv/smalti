import Foundation
import SmaltiCore

/// Shared layout files as pretty JSON with sorted keys, so a file reads and diffs well when it is shared (spec F7).
@MainActor
public final class SharedLayoutFiles: LayoutFiles {
    public init() {}

    public func write(_ layout: SharedLayout, to file: URL) throws(LayoutFileError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try encoder.encode(layout).write(to: file, options: .atomic)
        } catch {
            throw .unwritable(path: file.path(percentEncoded: false), reason: error.localizedDescription)
        }
    }

    /// Checks the size before reading: a file over the limit is refused without loading it.
    public func read(from file: URL) throws(LayoutFileError) -> SharedLayout {
        let path = file.path(percentEncoded: false)
        let data: Data
        do {
            let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int ?? 0
            guard size <= SharedLayout.maximumBytes else { throw LayoutFileError.invalid(.tooLarge(bytes: size)) }
            data = try Data(contentsOf: file)
        } catch let error as LayoutFileError {
            throw error
        } catch {
            throw .unreadable(path: path, reason: error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(SharedLayout.self, from: data)
        } catch {
            throw .invalid(.notJSON(Self.describe(error)))
        }
    }

    private static func describe(_ error: any Error) -> LayoutJSONProblem {
        guard let decoding = error as? DecodingError else { return .other(error.localizedDescription) }
        switch decoding {
        case .keyNotFound(let key, _): return .missingKey(key.stringValue)
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? .invalid : .invalidValue(path: path)
        @unknown default: return .invalid
        }
    }
}
