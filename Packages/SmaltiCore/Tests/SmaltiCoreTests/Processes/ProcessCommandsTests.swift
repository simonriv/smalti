import SmaltiCore
import Testing

@Suite("Process commands and shortcuts")
struct ProcessCommandsTests {
    @Test(arguments: [
        (CommandID.processesToggle, "⇧⌘M"), (.portsToggle, "⇧⌘U"), (.processesStop, "⌘⌫"),
        (.processesLowerPriority, "⇧⌘↓"), (.processesTree, "⌘T"), (.processesSort, "⇧⌘S"),
    ])
    func shortcutsOfTheSpec(command: CommandID, display: String) {
        #expect(Keymap.standard.chord(for: command)?.display == display)
    }

    @Test func noneUsesOptionAlone() {
        for command in CommandID.processes {
            #expect(Keymap.standard.chord(for: command)?.usesOptionAlone == false)
        }
    }

    @Test func backspaceParsesFromTheConfig() throws {
        let chord = try KeyChord.parse("cmd+backspace")

        #expect(chord.display == "⌘⌫")
        #expect(Keymap.standard.command(for: chord) == .processesStop)
    }

    @Test func allSixAreInThePalette() throws {
        let root = try WorkingDirectory(path: "/tmp")
        let set = WorkspaceSet(first: .empty(name: "tmp", rootDirectory: root, layout: DwindleLayout()))
        let titles = CommandCatalog.commands(
            for: CatalogState(workspaces: set), keymap: .standard,
            layouts: .standard, texts: .spanish
        ).map(\.id)

        for command in CommandID.processes { #expect(titles.contains(command)) }
    }

    @Test func helpHasAProcessesSection() {
        let section = HelpCatalog.sections(keymap: .standard, texts: .english).first { $0.title == "Processes and Ports" }

        #expect(section?.entries.map(\.title) == [
            "Open Processes", "Open Ports in Use", "Stop the Selected Process", "Lower the Selected Process’s Priority",
            "Show Processes as a Tree", "Change the Order of Processes and Ports",
        ])
    }

    @Test func contextualOnesAreTheFourInsideTheView() {
        #expect(CommandID.processesContextual == [.processesStop, .processesLowerPriority, .processesTree, .processesSort])
    }

    @Test func allAreStandard() {
        for command in CommandID.processes { #expect(CommandID.allStandard.contains(command)) }
    }
}
