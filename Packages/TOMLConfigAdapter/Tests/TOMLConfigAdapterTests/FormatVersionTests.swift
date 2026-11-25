import Foundation
import SmaltiCore
import Testing

@testable import TOMLConfigAdapter

/// F7.6: `config.toml` and `theme.toml` carry a format version; an older Smalti reads a newer file as far as it can
/// and never rewrites it.
@MainActor
@Suite("Config format version")
struct FormatVersionTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "smalti-version-\(UUID())")
    private var configFile: URL { directory.appending(path: "config.toml") }
    private var themeFile: URL { directory.appending(path: "theme.toml") }

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func store() -> TOMLConfigStore { TOMLConfigStore(config: configFile, theme: themeFile) }

    private func write(_ text: String, to file: URL) throws { try Data(text.utf8).write(to: file) }

    @Test func currentVersionIsAccepted() throws {
        let config = try TOMLConfigParser.parse("version = 1\n[appearance]\nblur = 12\n", file: "config.toml")

        #expect(config.appearance.blur == 12)
    }

    @Test func unknownKeyWithoutVersionIsStillAnError() {
        #expect(throws: ConfigError.self) { try TOMLConfigParser.parse("[nueva]\nx = 1\n", file: "config.toml") }
    }

    @Test func unknownKeyAtCurrentVersionIsStillAnError() {
        #expect(throws: ConfigError.self) {
            try TOMLConfigParser.parse("version = 1\n[appearance]\nx = 1\n", file: "config.toml")
        }
    }

    @Test(arguments: ["version = 0", "version = -1", "version = 1.5", #"version = "2""#])
    func invalidVersionIsAnError(_ line: String) {
        #expect(throws: ConfigError.self) { try TOMLConfigParser.parse(line + "\n", file: "config.toml") }
    }

    @Test func newerConfigAppliesWhatItKnowsAndWarnsAboutTheRest() throws {
        try write("version = 2\n[nueva]\na = 1\n[appearance]\nblur = 12\nfuturo = true\n", to: configFile)
        let store = store()

        let config = try store.reload()

        #expect(config.appearance.blur == 12)
        #expect(
            store.warnings() == [
                .newerFormat(file: "config.toml", version: 2, ignored: ["nueva", "appearance.futuro"])
            ])
    }

    @Test func newerConfigWithOnlyKnownKeysHasNoWarning() throws {
        try write("version = 2\n[appearance]\nblur = 12\n", to: configFile)
        let store = store()

        _ = try store.reload()

        #expect(store.warnings().isEmpty)
    }

    @Test func newerConfigWithAnInvalidKnownValueIsStillAnError() throws {
        try write("version = 2\n[appearance]\nblur = \"mucho\"\n", to: configFile)

        #expect(throws: ConfigError.self) { try store().reload() }
    }

    @Test func newerThemeIsReadLeniently() throws {
        try write("version = 2\n[appearance]\nblur = 20\nbrillo = 3\n", to: themeFile)
        let store = store()

        let config = try store.reload()

        #expect(config.appearance.blur == 20)
        #expect(store.warnings() == [.newerFormat(file: "theme.toml", version: 2, ignored: ["appearance.brillo"])])
    }

    @Test func newerWarningMessage() {
        #expect(
            ConfigWarning.newerFormat(file: "config.toml", version: 2, ignored: ["nueva", "appearance.futuro"]).message
                == "config.toml es de una versión más nueva de Smalti (2): se ignoran nueva, appearance.futuro")
    }

    @Test func themeWriterStartsWithItsVersion() {
        let lines = TOMLWriter.text(AppearanceDocument(config: .defaults)).split(
            separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.prefix(4).contains("version = 1"))
    }

    @Test func appearanceStoreNeverOverwritesANewerTheme() throws {
        let newer = "version = 2\n[appearance]\nblur = 20\nbrillo = 3\n"
        try write(newer, to: themeFile)
        let appearance = TOMLAppearanceStore(file: themeFile)

        #expect(throws: ConfigError.self) { try appearance.save(AppearanceDocument(config: .defaults)) }
        #expect(try String(contentsOf: themeFile, encoding: .utf8) == newer)
    }

    @Test func newerThemeSaveErrorSaysWhy() throws {
        try write("version = 2\n", to: themeFile)

        do {
            try TOMLAppearanceStore(file: themeFile).save(AppearanceDocument(config: .defaults))
            Issue.record("the newer theme was overwritten")
        } catch {
            #expect(error.reason == "theme.toml es de una versión más nueva de Smalti: no se sobrescribe")
        }
    }
}
