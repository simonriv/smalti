import Foundation

/// Reads `Fixtures/<name>.toml` next to this file.
enum Fixture {
    static let directory = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")

    static func url(_ name: String) -> URL {
        directory.appending(path: "\(name).toml")
    }

    static func text(_ name: String) throws -> String {
        try String(contentsOf: url(name), encoding: .utf8)
    }
}
