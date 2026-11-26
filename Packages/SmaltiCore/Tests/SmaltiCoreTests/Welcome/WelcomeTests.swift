import Foundation
import SmaltiCore
import SmaltiCoreTestSupport
import Testing

@Suite("Welcome content")
struct WelcomeContentTests {
    @Test func shortcutsComeFromTheKeymap() {
        let shortcuts = WelcomeContent.shortcuts(keymap: .standard, texts: .spanish)

        #expect(
            shortcuts.map(\.label) == [
                "Paleta de comandos", "Ayuda y atajos", "Observatorio", "Sesiones de agentes", "Dividir panel",
                "Saltar al agente que te espera", "Nuevo workspace",
            ])
        #expect(shortcuts.map(\.keys) == ["⌘K", "⌘?", "⇧⌘A", "⇧⌘O", "⌘D", "⌘J", "⌃⌘N"])
    }

    @Test func aChangedChordShowsChanged() throws {
        let keymap = try Keymap.standard.overriding([try KeyChord.parse("cmd+p"): .paletteOpen])

        #expect(WelcomeContent.shortcuts(keymap: keymap, texts: .english).first?.keys == "⌘P")
    }

    @Test func anUnboundCommandSaysInPalette() throws {
        let keymap = try Keymap.standard.overriding([try KeyChord.parse("cmd+j"): nil])

        #expect(WelcomeContent.shortcuts(keymap: keymap, texts: .english)[5].keys == "in ⌘K")
    }

    @Test func subtitleNamesThePalettesChord() {
        #expect(
            WelcomeContent.subtitle(keymap: .standard, texts: .english)
                == "Everything is in ⌘K: type what you want to do.")
    }

    @Test func catalogsHaveBothLanguages() {
        #expect(TextCatalogAudit.problems(spanish: WelcomeTexts.spanish, english: WelcomeTexts.english).isEmpty)
    }
}

@Suite("Welcome state")
struct WelcomeStateTests {
    private func state() -> WelcomeState {
        WelcomeState(claude: .notInstalled, neovim: .unknown, theme: .obsidiana)
    }

    @Test func startsOnClaude() {
        #expect(state().selected == .claude)
    }

    @Test func moveStopsAtTheEdges() {
        var welcome = state()
        welcome.move(-1)
        #expect(welcome.selected == .claude)
        welcome.move(1)
        welcome.move(1)
        welcome.move(1)
        #expect(welcome.selected == .theme)
    }

    @Test func cycleThemeWrapsAround() {
        var welcome = state()
        welcome.cycleTheme(-1)
        #expect(welcome.theme == .bosque)
        welcome.cycleTheme(1)
        welcome.cycleTheme(1)
        #expect(welcome.theme == .niebla)
    }

    @Test func finishKeepsTheChosenTheme() {
        var welcome = state()
        welcome.cycleTheme(1)

        #expect(welcome.finish() == WelcomeOutcome(theme: .niebla, marksDone: true))
    }

    @Test func skipRestoresTheOriginalTheme() {
        var welcome = state()
        welcome.cycleTheme(1)

        #expect(welcome.skip() == WelcomeOutcome(theme: .obsidiana, marksDone: true))
    }

    @Test func skipWithoutChangesTouchesNoTheme() {
        #expect(state().skip() == WelcomeOutcome(theme: nil, marksDone: true))
        #expect(state().finish() == WelcomeOutcome(theme: nil, marksDone: true))
    }

    @Test func installableOnlyWhenTheStateAllowsIt() {
        #expect(state().canInstall(.claude))
        #expect(!state().canInstall(.neovim))
        #expect(!state().canInstall(.theme))
    }

    @Test func rowStatusTexts() {
        var welcome = state()
        welcome.claude = .installed

        #expect(welcome.status(of: .claude, texts: .spanish) == "instalada")
        #expect(welcome.status(of: .neovim, texts: .spanish) == "no detectada: ver la documentación")
        #expect(welcome.status(of: .theme, texts: .english) == "‹ Obsidian ›")
    }
}

@MainActor
@Suite("ShowWelcome")
struct ShowWelcomeTests {
    @Test func freshStateShowsIt() async {
        let record = InMemoryWelcomeRecord()

        #expect(await ShowWelcome(record: record).shouldShowAtLaunch(hasSavedSession: false))
        #expect(await record.isDone == false)
    }

    @Test func doneRecordHidesIt() async throws {
        let record = InMemoryWelcomeRecord(isDone: true)

        #expect(await !ShowWelcome(record: record).shouldShowAtLaunch(hasSavedSession: false))
    }

    @Test func previousSessionHidesItAndMarksIt() async {
        let record = InMemoryWelcomeRecord()

        #expect(await !ShowWelcome(record: record).shouldShowAtLaunch(hasSavedSession: true))
        #expect(await record.isDone)
    }

    @Test func doneAndSessionHidesIt() async {
        let record = InMemoryWelcomeRecord(isDone: true)

        #expect(await !ShowWelcome(record: record).shouldShowAtLaunch(hasSavedSession: true))
    }
}

@Suite("Welcome record contract")
struct InMemoryWelcomeRecordContractTests {
    @Test func inMemoryRecordFollowsTheContract() async {
        #expect(await WelcomeRecordContract.problems { InMemoryWelcomeRecord() }.isEmpty)
    }
}

/// Review 1 (M5): "in ⌘K" names the palette's chord in effect.
@Suite("In-palette hint follows the keymap")
struct InPaletteHintTests {
    private func keymap() throws -> Keymap {
        try Keymap.standard.overriding([
            try KeyChord.parse("cmd+k"): nil, try KeyChord.parse("cmd+p"): .paletteOpen,
            try KeyChord.parse("cmd+j"): nil,
        ])
    }

    @Test func welcomeNamesTheReboundPalette() throws {
        #expect(WelcomeContent.shortcuts(keymap: try keymap(), texts: .english)[5].keys == "in ⌘P")
    }

    @Test func helpNamesTheReboundPalette() throws {
        let entries = HelpCatalog.sections(keymap: try keymap(), texts: .spanish).flatMap(\.entries)

        #expect(entries.first { $0.command == .agentJump }?.keys == "en ⌘P")
    }
}

/// F7.7: the welcome card reuses the feedback box's and the palette's tokens; only its width is its own (560 pt).
@Suite("Welcome tokens")
struct WelcomeTokensTests {
    @Test func obsidianWelcomeComesFromTheExistingTokens() {
        let theme = Theme.obsidian

        #expect(theme.welcome.width == 560)
        #expect(theme.welcome.padding == theme.feedback.padding)
        #expect(theme.welcome.titleFontSize == theme.feedback.titleFontSize)
        #expect(theme.welcome.rowHeight == theme.feedback.choiceHeight)
        #expect(theme.welcome.lineGap == theme.feedback.lineGap)
        #expect(theme.welcome.topOffset == theme.feedback.topOffset)
    }
}
