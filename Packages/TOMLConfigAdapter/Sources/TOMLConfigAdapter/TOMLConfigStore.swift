import Foundation
import SmaltiCore

/// `ConfigStore` backed by a TOML file, normally `~/.config/smalti/config.toml`. A missing file means defaults.
@MainActor
public final class TOMLConfigStore: ConfigStore {
    private static let unreadableReason = "no se pudo leer el archivo"
    private static let noPermissionCause = "sin permiso de lectura"
    private static let notUTF8Reason = "el archivo no está en UTF-8"

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
        guard let text = String(validating: try contents(), as: UTF8.self) else {
            throw failure(Self.notUTF8Reason)
        }
        return try TOMLConfigParser.parse(text, file: displayPath)
    }

    private func contents() throws(ConfigError) -> Data {
        do {
            return try Data(contentsOf: file)
        } catch {
            throw failure("\(Self.unreadableReason): \(Self.cause(of: error))")
        }
    }

    private func failure(_ reason: String) -> ConfigError {
        ConfigError(file: displayPath, line: nil, key: nil, reason: reason)
    }

    private static func cause(of error: any Error) -> String {
        if let cocoa = error as? CocoaError, cocoa.code == .fileReadNoPermission { return noPermissionCause }
        return error.localizedDescription
    }
}
