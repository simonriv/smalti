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
        "macos-option-as-alt = false",
        "shell-integration = zsh",
        "confirm-close-surface = false",
        "adjust-cell-height = 23%",
    ])
    func containsSetting(_ line: String) {
        #expect(lines.contains(line))
    }

    @Test func configStartsWithKeybindClear() {
        let firstLine = GhosttyConfigText.render(Theme.obsidian.terminal).split(separator: "\n").first

        #expect(firstLine == "keybind = clear")
    }

    @Test func configRebindsOnlyCopyAndPaste() {
        let keybinds = GhosttyConfigText.render(Theme.obsidian.terminal)
            .split(separator: "\n")
            .filter { $0.hasPrefix("keybind = ") }

        #expect(
            keybinds == [
                "keybind = clear", "keybind = super+c=copy_to_clipboard", "keybind = super+v=paste_from_clipboard",
            ])
    }

    @Test func renderNeverInjectsLinesFromFontFamily() {
        var settings = AppearanceSettings.obsidian
        settings.fontFamily = "X\"\ncommand = /bin/sh"
        let appearance = Theme.obsidian.applying(settings).terminal

        let lines = GhosttyConfigText.render(appearance).split(separator: "\n")

        #expect(!lines.contains { $0.hasPrefix("command") })
        #expect(lines.filter { $0 == "keybind = clear" }.count == 1)
    }

    @Test(arguments: ["X\"Y", "X\\Y", "X\nY", "X\rY", "X\u{7}Y"])
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
