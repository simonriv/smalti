import SmaltiCore
import Testing

@Suite("Timeline commands and shortcuts")
struct TimelineCommandsTests {
    @Test(arguments: [(CommandID.timelineToggle, "⇧⌘T"), (.timelineCopyCall, "⇧⌘C")])
    func shortcutsOfTheSpec(command: CommandID, display: String) {
        #expect(Keymap.standard.chord(for: command)?.display == display)
    }

    @Test func searchAndCopyHaveNoChordOfTheirOwn() {
        #expect(Keymap.standard.chord(for: .timelineSearch) == nil)
        #expect(Keymap.standard.chord(for: .timelineCopy) == nil)
    }

    @Test func noneUsesOptionAlone() {
        for command in CommandID.timeline { #expect(Keymap.standard.chord(for: command)?.usesOptionAlone != true) }
    }

    @Test func allFourAreInThePaletteTheHelpAndTheMenu() throws {
        let root = try WorkingDirectory(path: "/tmp")
        let set = WorkspaceSet(first: .empty(name: "tmp", rootDirectory: root, layout: DwindleLayout()))
        let palette = CommandCatalog.commands(
            for: CatalogState(workspaces: set), keymap: .standard, layouts: .standard, texts: .spanish
        ).map(\.id)
        let help = HelpCatalog.sections(keymap: .standard, texts: .english).flatMap(\.entries).map(\.title)

        for command in CommandID.timeline { #expect(palette.contains(command)) }
        #expect(help.contains("Open the Timeline"))
        #expect(help.contains("Copy the Selected Call"))
    }

    @Test func copyCallPassesToTheTerminalOutsideTheTimeline() throws {
        let press = KeyPress(try #require(Keymap.standard.chord(for: .timelineCopyCall)))

        #expect(CommandID.timelineContextual == [.timelineCopyCall])
        #expect(KeyRouting.decide(press, keymap: .standard, context: .overlay(allowing: [])) == .passThrough)
    }

    @Test func allAreStandard() {
        for command in CommandID.timeline { #expect(CommandID.allStandard.contains(command)) }
    }
}
