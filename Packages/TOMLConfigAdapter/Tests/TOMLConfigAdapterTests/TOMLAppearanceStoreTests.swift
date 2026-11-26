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
        let store = TOMLAppearanceStore(file: themeFile, texts: .spanish)
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

        try TOMLAppearanceStore(file: themeFile, texts: .spanish).save(document)

        #expect(try readBack() == document)
    }

    @Test(arguments: PromptIcons.allCases)
    func roundTripIcons(_ icons: PromptIcons) throws {
        var document = AppearanceDocument(config: .defaults)
        document.prompt.icons = icons

        try TOMLAppearanceStore(file: themeFile, texts: .spanish).save(document)

        #expect(try readBack() == document)
    }

    @Test(arguments: PromptSymbol.allCases)
    func roundTripSymbols(_ symbol: PromptSymbol) throws {
        var document = AppearanceDocument(config: .defaults)
        document.prompt.symbol = symbol

        try TOMLAppearanceStore(file: themeFile, texts: .spanish).save(document)

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

        try TOMLAppearanceStore(file: themeFile, texts: .spanish).save(document)

        #expect(try readBack() == document)
    }

    @Test func emptyModulesRoundTrip() throws {
        var document = AppearanceDocument(config: .defaults)
        document.prompt.modules = []

        try TOMLAppearanceStore(file: themeFile, texts: .spanish).save(document)

        #expect(try readBack() == document)
    }

    @Test func accentIsPreservedOnRewrite() throws {
        var document = AppearanceDocument(config: .defaults)
        document.appearance.accent = try RGBAColor(hex: "#ff8000")

        try TOMLAppearanceStore(file: themeFile, texts: .spanish).save(document)

        #expect(try readBack().appearance.accent == (try RGBAColor(hex: "#ff8000")))
    }

    @Test func fileStartsWithTheExplainingComment() throws {
        try TOMLAppearanceStore(file: themeFile, texts: .spanish).save(AppearanceDocument(config: .defaults))

        let text = try String(contentsOf: themeFile, encoding: .utf8)

        #expect(text.hasPrefix("# Lo escribe Smalti (Apariencia y Estudio de prompt)."))
        #expect(text.contains("theme = \"obsidiana\""))
        #expect(
            text.contains(
                "modules = [\"directory\", \"git-branch\", \"git-status\", \"runtime\", \"duration\", \"agents\"]"))
    }

    @Test func saveMergesExternalEditFirst() throws {
        let store = TOMLAppearanceStore(file: themeFile, texts: .spanish)
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

    /// Final review (I1): the saved document carries the hand edit, so saving it again keeps the edit.
    @Test func secondSaveKeepsTheHandEdit() throws {
        let store = TOMLAppearanceStore(file: themeFile, texts: .spanish)
        let base = AppearanceDocument(config: .defaults)
        try store.save(base)
        let edited = try String(contentsOf: themeFile, encoding: .utf8).replacingOccurrences(
            of: "blur = 28", with: "blur = 12")
        try edited.write(to: themeFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: themeFile.path(percentEncoded: false))
        var ui = base
        ui.appearance.glassOpacity = 0.7

        var next = try store.save(ui)
        next.appearance.glassOpacity = 0.8
        try store.save(next)

        #expect(try readBack().appearance.blur == 12)
    }

    @Test func writeLeavesNoTemporaryFiles() throws {
        try TOMLAppearanceStore(file: themeFile, texts: .spanish).save(AppearanceDocument(config: .defaults))

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))

        #expect(names == ["theme.toml"])
    }

    @Test func missingDirectoryIsCreated() throws {
        let nested = directory.appending(path: "a/b/theme.toml")

        try TOMLAppearanceStore(file: nested, texts: .spanish).save(AppearanceDocument(config: .defaults))

        #expect(FileManager.default.fileExists(atPath: nested.path(percentEncoded: false)))
    }

    @Test func storeHonorsTheContract() {
        let file = themeFile
        let config = configFile
        AppearanceStoreContract.verify {
            (
                TOMLAppearanceStore(file: file, texts: .spanish),
                { (try? TOMLConfigStore(config: config, theme: file).reload()).map(AppearanceDocument.init(config:)) }
            )
        }
    }
}

/// Block 3 review (I5, M7–M9): the first save of a session, ANSI per index across files, keys deleted by hand, a broken
/// file and a symlinked theme.toml.
@MainActor
@Suite("TOMLAppearanceStore · review")
struct TOMLAppearanceStoreReviewTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "smalti-store-review-\(UUID())")
    private var themeFile: URL { directory.appending(path: "theme.toml") }
    private var configFile: URL { directory.appending(path: "config.toml") }

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func readBack() throws -> AppearanceDocument {
        AppearanceDocument(config: try TOMLConfigStore(config: configFile, theme: themeFile).reload())
    }

    private func bumpDate() throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: themeFile.path(percentEncoded: false))
    }

    @Test func firstSaveOfTheSessionKeepsAHandEdit() throws {
        try TOMLAppearanceStore(file: themeFile, texts: .spanish).save(AppearanceDocument(config: .defaults))
        let store = TOMLAppearanceStore(file: themeFile, texts: .spanish)
        store.remember(try readBack())
        let edited = try String(contentsOf: themeFile, encoding: .utf8).replacingOccurrences(
            of: "gap = 8", with: "gap = 3")
        try edited.write(to: themeFile, atomically: true, encoding: .utf8)
        try bumpDate()
        var ui = AppearanceDocument(config: .defaults)
        ui.appearance.radius = 5

        try store.save(ui)

        #expect(try readBack().appearance.gap == 3)
        #expect(try readBack().appearance.radius == 5)
    }

    @Test func keyDeletedByHandIsRespected() throws {
        let store = TOMLAppearanceStore(file: themeFile, texts: .spanish)
        var base = AppearanceDocument(config: .defaults)
        base.appearance.accent = try RGBAColor(hex: "#ff0000")
        try store.save(base)
        let edited = try String(contentsOf: themeFile, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("accent") }.joined(separator: "\n")
        try edited.write(to: themeFile, atomically: true, encoding: .utf8)
        try bumpDate()
        var ui = base
        ui.appearance.theme = .bosque

        try store.save(ui)

        #expect(try readBack().appearance.accent == nil)
    }

    @Test func brokenFileIsBackedUpBeforeOverwriting() throws {
        let store = TOMLAppearanceStore(file: themeFile, texts: .spanish)
        try store.save(AppearanceDocument(config: .defaults))
        try "[appearance\nroto = ".write(to: themeFile, atomically: true, encoding: .utf8)
        try bumpDate()

        try store.save(AppearanceDocument(config: .defaults))

        let backup = directory.appending(path: "theme.toml.bak")
        #expect((try? String(contentsOf: backup, encoding: .utf8)) == "[appearance\nroto = ")
    }

    @Test func symlinkedFileStaysASymlink() throws {
        let real = directory.appending(path: "dotfiles/theme.toml")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: themeFile, withDestinationURL: real)

        try TOMLAppearanceStore(file: themeFile, texts: .spanish).save(AppearanceDocument(config: .defaults))

        let kind = try FileManager.default.attributesOfItem(atPath: themeFile.path(percentEncoded: false))[.type]
        #expect(kind as? FileAttributeType == .typeSymbolicLink)
        #expect(try String(contentsOf: real, encoding: .utf8).contains("[appearance]"))
    }
}

/// Block 3 review (M7): ANSI edits combine per index across config.toml and theme.toml.
@MainActor
@Suite("theme.toml reading · review")
struct ThemeReaderReviewTests {
    @Test func ansiOverridesMergePerIndex() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "smalti-ansi-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "[appearance.ansi.obsidiana]\n1 = \"#111111\"\n".write(
            to: directory.appending(path: "config.toml"), atomically: true, encoding: .utf8)
        try "[appearance.ansi.obsidiana]\n2 = \"#222222\"\n".write(
            to: directory.appending(path: "theme.toml"), atomically: true, encoding: .utf8)

        let config = try TOMLConfigStore(
            config: directory.appending(path: "config.toml"), theme: directory.appending(path: "theme.toml")
        ).reload()

        #expect(config.appearance.ansiOverrides[.obsidiana]?.colors.keys.sorted() == [1, 2])
    }
}
