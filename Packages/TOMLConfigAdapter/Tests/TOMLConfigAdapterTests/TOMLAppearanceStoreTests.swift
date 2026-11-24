import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

import TOMLConfigAdapter

/// Spec F5, `theme.toml`: the UI writes the whole file, and what it writes reads back exactly.
@MainActor
@Suite("TOMLAppearanceStore")
struct TOMLAppearanceStoreTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "smalti-store-\(UUID())")
    private var themeFile: URL { directory.appending(path: "theme.toml") }
    private var configFile: URL { directory.appending(path: "config.toml") }

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func readBack() throws -> AppearanceDocument {
        AppearanceDocument(config: try TOMLConfigStore(config: configFile, theme: themeFile).reload())
    }

    @Test func roundTripEveryEnum() throws {
        let store = TOMLAppearanceStore(file: themeFile)
        var round = 0
        for theme in ThemeID.allCases {
            for buttons in WindowButtons.allCases {
                for style in PromptStyleID.allCases {
                    for layout in PromptLayout.allCases {
                        var document = AppearanceDocument(config: .defaults)
                        document.appearance.theme = theme
                        document.buttons = buttons
                        document.prompt.style = style
                        document.prompt.layout = layout
                        round += 1
                        document.prompt.icons = PromptIcons.allCases[round % PromptIcons.allCases.count]
                        document.prompt.symbol = PromptSymbol.allCases[round % PromptSymbol.allCases.count]
                        document.prompt.source = layout == .oneLine ? .shell : .smalti

                        try store.save(document)

                        #expect(try readBack() == document)
                    }
                }
            }
        }
    }

    @Test(arguments: [(0.30, 0.0), (0.95, 48.0), (0.62, 28.0), (0.6200000000000001, 27.5)])
    func roundTripRangeEdges(_ glass: Double, _ blur: Double) throws {
        var document = AppearanceDocument(config: .defaults)
        document.appearance.glassOpacity = glass
        document.appearance.blur = blur

        try TOMLAppearanceStore(file: themeFile).save(document)

        #expect(try readBack() == document)
    }

    @Test(arguments: PromptIcons.allCases)
    func roundTripIcons(_ icons: PromptIcons) throws {
        var document = AppearanceDocument(config: .defaults)
        document.prompt.icons = icons

        try TOMLAppearanceStore(file: themeFile).save(document)

        #expect(try readBack() == document)
    }

    @Test(arguments: PromptSymbol.allCases)
    func roundTripSymbols(_ symbol: PromptSymbol) throws {
        var document = AppearanceDocument(config: .defaults)
        document.prompt.symbol = symbol

        try TOMLAppearanceStore(file: themeFile).save(document)

        #expect(try readBack() == document)
    }

    @Test func roundTripModulesAndAnsiAndFont() throws {
        var document = AppearanceDocument(config: .defaults)
        document.prompt.modules = [.cloud, .time, .directory]
        document.appearance.ansiOverrides = [
            .bosque: try ANSIOverrides([1: try RGBAColor(hex: "#ff6b6b"), 15: try RGBAColor(hex: "#000000")]),
            .niebla: try ANSIOverrides([0: try RGBAColor(hex: "#123456")]),
        ]
        document.appearance.fontFamily = "Berkeley Mono"
        document.appearance.protectLegibility = false

        try TOMLAppearanceStore(file: themeFile).save(document)

        #expect(try readBack() == document)
    }

    @Test func emptyModulesRoundTrip() throws {
        var document = AppearanceDocument(config: .defaults)
        document.prompt.modules = []

        try TOMLAppearanceStore(file: themeFile).save(document)

        #expect(try readBack() == document)
    }

    @Test func accentIsPreservedOnRewrite() throws {
        var document = AppearanceDocument(config: .defaults)
        document.appearance.accent = try RGBAColor(hex: "#ff8000")

        try TOMLAppearanceStore(file: themeFile).save(document)

        #expect(try readBack().appearance.accent == (try RGBAColor(hex: "#ff8000")))
    }

    @Test func fileStartsWithTheExplainingComment() throws {
        try TOMLAppearanceStore(file: themeFile).save(AppearanceDocument(config: .defaults))

        let text = try String(contentsOf: themeFile, encoding: .utf8)

        #expect(text.hasPrefix("# Lo escribe Smalti (Apariencia y Estudio de prompt)."))
        #expect(text.contains("theme = \"obsidiana\""))
        #expect(
            text.contains(
                "modules = [\"directory\", \"git-branch\", \"git-status\", \"runtime\", \"duration\", \"agents\"]"))
    }

    @Test func saveMergesExternalEditFirst() throws {
        let store = TOMLAppearanceStore(file: themeFile)
        let base = AppearanceDocument(config: .defaults)
        try store.save(base)
        // Someone edits the file by hand while the UI is open.
        let edited = try String(contentsOf: themeFile, encoding: .utf8).replacingOccurrences(
            of: "blur = 28", with: "blur = 12")
        try edited.write(to: themeFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: themeFile.path(percentEncoded: false))
        var ui = base
        ui.appearance.theme = .bosque

        try store.save(ui)

        let saved = try readBack()
        #expect(saved.appearance.theme == .bosque)
        #expect(saved.appearance.blur == 12)
    }

    @Test func writeLeavesNoTemporaryFiles() throws {
        try TOMLAppearanceStore(file: themeFile).save(AppearanceDocument(config: .defaults))

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))

        #expect(names == ["theme.toml"])
    }

    @Test func missingDirectoryIsCreated() throws {
        let nested = directory.appending(path: "a/b/theme.toml")

        try TOMLAppearanceStore(file: nested).save(AppearanceDocument(config: .defaults))

        #expect(FileManager.default.fileExists(atPath: nested.path(percentEncoded: false)))
    }

    @Test func storeHonorsTheContract() {
        let file = themeFile
        let config = configFile
        AppearanceStoreContract.verify {
            (
                TOMLAppearanceStore(file: file),
                { (try? TOMLConfigStore(config: config, theme: file).reload()).map(AppearanceDocument.init(config:)) }
            )
        }
    }
}
