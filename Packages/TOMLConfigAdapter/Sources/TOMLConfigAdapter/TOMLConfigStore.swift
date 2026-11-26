import Foundation
import SmaltiCore

/// `ConfigStore` backed by a TOML file, normally `~/.config/smalti/config.toml`. A missing file means defaults.
@MainActor
public final class TOMLConfigStore: ConfigStore {

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
        let parsed =
            try configText.map { (text) throws(ConfigError) in
                try TOMLConfigParser.read(text, file: displayPath)
            } ?? TOMLConfigParser.Parsed(config: .defaults, warning: nil)
        var config = parsed.config
        var warnings = [parsed.warning].compactMap { $0 }
        if let themeFile, let themeText = try text(of: themeFile) {
            let themePath = themeFile.path(percentEncoded: false)
            let theme = try TOMLConfigParser.readTheme(themeText, file: themePath, over: config)
            config = theme.config
            warnings += [theme.warning].compactMap { $0 }
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
            throw failure(.notUTF8, file: path)
        }
        return text
    }

    private func contents(of url: URL) throws(ConfigError) -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw failure(Self.problem(reading: error), file: url.path(percentEncoded: false))
        }
    }

    private func failure(_ problem: ConfigProblem, file: String) -> ConfigError {
        ConfigError(file: file, line: nil, key: nil, problem: problem)
    }

    private static func problem(reading error: any Error) -> ConfigProblem {
        if let cocoa = error as? CocoaError, cocoa.code == .fileReadNoPermission { return .noReadPermission }
        return .unreadableFile(detail: error.localizedDescription)
    }
}
