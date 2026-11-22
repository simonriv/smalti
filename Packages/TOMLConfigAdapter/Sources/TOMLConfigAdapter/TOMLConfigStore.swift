import Foundation
import SmaltiCore

/// `ConfigStore` backed by a TOML file, normally `~/.config/smalti/config.toml`. A missing file means defaults.
@MainActor
public final class TOMLConfigStore: ConfigStore {
    private static let unreadableReason = "no se pudo leer el archivo"

    private let file: URL
    private var lastValid = SmaltiConfig.defaults

    public init(file: URL) {
        self.file = file
    }

    public func current() -> SmaltiConfig {
        lastValid
    }

    public func reload() throws(ConfigError) -> SmaltiConfig {
        lastValid = try read()
        return lastValid
    }

    private var displayPath: String {
        file.path(percentEncoded: false)
    }

    private func read() throws(ConfigError) -> SmaltiConfig {
        guard FileManager.default.fileExists(atPath: displayPath) else { return .defaults }
        let text: String
        do {
            text = try String(contentsOf: file, encoding: .utf8)
        } catch {
            throw ConfigError(file: displayPath, line: nil, key: nil, reason: Self.unreadableReason)
        }
        return try TOMLConfigParser.parse(text, file: displayPath)
    }
}
