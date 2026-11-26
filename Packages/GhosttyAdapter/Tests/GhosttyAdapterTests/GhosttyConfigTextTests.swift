@testable import GhosttyAdapter
import SmaltiCore
import Testing

@Suite("Ghostty config text")
struct GhosttyConfigTextTests {
    private let lines = Set(GhosttyConfigText.render(Theme.obsidian.terminal).split(separator: "\n").map(String.init))

    @Test(arguments: [
        #"font-family = "JetBrains Mono""#,
        "font-size = 13",
        "foreground = #d7dae0",
        "cursor-color = #7aa2f7",
        "background-opacity = 0",
        "window-padding-x = 16",
        "window-padding-y = 12",
        "window-padding-balance = false",
        "shell-integration = zsh",
        "confirm-close-surface = true",
        "adjust-cell-height = 23%",
    ])
    func containsSetting(_ line: String) {
        #expect(lines.contains(line))
    }

    @Test func configStartsWithKeybindClear() {
        let firstLine = GhosttyConfigText.render(Theme.obsidian.terminal).split(separator: "\n").first

        #expect(firstLine == "keybind = clear")
    }

    /// F4.5: copy and paste are Smalti commands (`KeyRouter` → `TerminalEngine.perform`), so libghostty binds nothing.
    @Test func configHasOnlyClearKeybind() {
        let keybinds = GhosttyConfigText.render(Theme.obsidian.terminal)
            .split(separator: "\n")
            .filter { $0.hasPrefix("keybind = ") }

        #expect(keybinds == ["keybind = clear"])
    }

    /// F4.5 T10: password prompts ask for secure keyboard entry by themselves.
    @Test func configEnablesAutoSecureInput() {
        let lines = GhosttyConfigText.render(Theme.obsidian.terminal).split(separator: "\n")

        #expect(lines.contains("macos-auto-secure-input = true"))
    }

    @Test func renderNeverInjectsLinesFromFontFamily() {
        var settings = AppearanceSettings.obsidian
        settings.fontFamily = "X\"\ncommand = /bin/sh"
        let appearance = Theme.obsidian.applying(settings).terminal

        let lines = GhosttyConfigText.render(appearance).split(separator: "\n")

        #expect(!lines.contains { $0.hasPrefix("command") })
        #expect(lines.filter { $0 == "keybind = clear" }.count == 1)
    }

    @Test(arguments: ["X\"Y", "X\\Y", "X\nY", "X\rY", "X\u{7}Y", String(repeating: "a", count: 101)])
    func unsafeFontFamilyLeavesTheEngineDefault(_ family: String) {
        var settings = AppearanceSettings.obsidian
        settings.fontFamily = family
        let appearance = Theme.obsidian.applying(settings).terminal

        let rendered = GhosttyConfigText.render(appearance)

        #expect(!rendered.contains("font-family"))
    }

    @Test func listsTheSixteenPaletteEntriesInOrder() {
        let palette = GhosttyConfigText.render(Theme.obsidian.terminal)
            .split(separator: "\n")
            .filter { $0.hasPrefix("palette = ") }

        #expect(palette.count == 16)
        #expect(palette.first == "palette = 0=#15161e")
        #expect(palette.last == "palette = 15=#c0caf5")
    }

    @Test func cellHeightFollowsTheThemeLineHeight() {
        #expect(GhosttyConfigText.cellHeightAdjustment(lineHeight: 1.62) == "23%")
    }

    @Test func naturalLineHeightNeedsNoAdjustment() {
        #expect(GhosttyConfigText.cellHeightAdjustment(lineHeight: GhosttyConfigText.naturalLineHeight) == "0%")
    }
}

/// F7.7 `[keyboard] option_as_meta`: `auto` leaves the choice to libghostty's layout detection.
@Suite("Ghostty option as meta")
struct GhosttyOptionAsMetaTests {
    private func optionLines(_ choice: OptionAsMeta) -> [String] {
        var appearance = Theme.obsidian.terminal
        appearance.optionAsMeta = choice
        return GhosttyConfigText.render(appearance).split(separator: "\n").map(String.init)
            .filter { $0.hasPrefix("macos-option-as-alt") }
    }

    @Test func autoWritesNoKey() {
        #expect(optionLines(.auto).isEmpty)
    }

    @Test(arguments: [
        (OptionAsMeta.never, "false"), (.always, "true"), (.left, "left"), (.right, "right"),
    ])
    func explicitChoicesAreWritten(choice: OptionAsMeta, value: String) {
        #expect(optionLines(choice) == ["macos-option-as-alt = \(value)"])
    }

    @Test func resizingKeepsTheChoice() {
        var appearance = Theme.obsidian.terminal
        appearance.optionAsMeta = .left

        #expect(appearance.withFontSize(20).optionAsMeta == .left)
    }
}
