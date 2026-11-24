import Foundation
import SmaltiCore

/// `ConfigStore` backed by a TOML file, normally `~/.config/smalti/config.toml`. A missing file means defaults.
@MainActor
public final class TOMLConfigStore: ConfigStore {
    private static let unreadableReason = "no se pudo leer el archivo"
    private static let noPermissionCause = "sin permiso de lectura"
    private static let notUTF8Reason = "el archivo no está en UTF-8"

    private let file: URL
    /// F5: written by the UI and read over `file` key by key; `nil` reads `file` alone.
    private let themeFile: URL?
    private var lastValid = SmaltiConfig.defaults
    private var lastWarnings: [ConfigWarning] = []

    public init(file: URL) {
        self.file = file
        themeFile = nil
    }

    public init(config: URL, theme: URL) {
        file = config
        themeFile = theme
    }

    public func warnings() -> [ConfigWarning] {
        lastWarnings
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
        let configText = try text(of: file)
        var config =
            try configText.map { (text) throws(ConfigError) in
                try TOMLConfigParser.parse(text, file: displayPath)
            } ?? .defaults
        var warnings: [ConfigWarning] = []
        if let themeFile, let themeText = try text(of: themeFile) {
            let themePath = themeFile.path(percentEncoded: false)
            config = try TOMLConfigParser.parseTheme(themeText, file: themePath, over: config)
            let repeated =
                try configText.map { (text) throws(ConfigError) in
                    try TOMLConfigParser.lookKeys(text, file: displayPath)
                        .intersection(try TOMLConfigParser.lookKeys(themeText, file: themePath))
                } ?? []
            if !repeated.isEmpty { warnings.append(.duplicatedKeys(repeated.sorted())) }
        }
        lastWarnings = warnings
        return config
    }

    /// The file's text, or `nil` when it does not exist.
    private func text(of url: URL) throws(ConfigError) -> String? {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let text = String(validating: try contents(of: url), as: UTF8.self) else {
            throw failure(Self.notUTF8Reason, file: path)
        }
        return text
    }

    private func contents(of url: URL) throws(ConfigError) -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw failure("\(Self.unreadableReason): \(Self.cause(of: error))", file: url.path(percentEncoded: false))
        }
    }

    private func failure(_ reason: String, file: String) -> ConfigError {
        ConfigError(file: file, line: nil, key: nil, reason: reason)
    }

    private static func cause(of error: any Error) -> String {
        if let cocoa = error as? CocoaError, cocoa.code == .fileReadNoPermission { return noPermissionCause }
        return error.localizedDescription
    }
}
