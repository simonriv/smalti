import GhosttyAdapter
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

    @Test func listsTheSixteenPaletteEntriesInOrder() {
        let palette = GhosttyConfigText.render(Theme.obsidian.terminal)
            .split(separator: "\n")
            .filter { $0.hasPrefix("palette = ") }

        #expect(palette.count == 16)
        #expect(palette.first == "palette = 0=#15161e")
        #expect(palette.last == "palette = 15=#c0caf5")
    }
}
