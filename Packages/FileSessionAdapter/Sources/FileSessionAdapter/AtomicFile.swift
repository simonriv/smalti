import Foundation

/// Writes through a temporary file in the same directory and renames it, so a half-written file never replaces
/// a good one.
enum AtomicFile {
    static func write(_ data: Data, to file: URL) throws(SessionArchiveFailure) {
        let temporary = file.deletingLastPathComponent().appending(path: ".\(file.lastPathComponent).\(UUID()).tmp")
        do {
            try data.write(to: temporary)
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw SessionArchiveFailure(file: file, cause: error)
        }
    }
}

struct SessionArchiveFailure: Error {
    let file: URL
    let cause: any Error

    var reason: String { String(describing: cause) }
}
