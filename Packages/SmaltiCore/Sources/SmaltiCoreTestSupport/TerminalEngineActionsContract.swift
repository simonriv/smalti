import SmaltiCore
import Testing

/// What every `TerminalEngine` does with the F4.5 operations on panes it does not have (never opened, or closed):
/// nothing, without crashing. Keys and menus can race a pane's close. Run it from each implementation's tests.
@MainActor
public enum TerminalEngineActionsContract {
    static let actions: [TerminalAction] = [
        .copy, .paste, .selectAll, .clear, .scroll(.pageUp), .scroll(.pageDown), .scroll(.top), .scroll(.bottom),
        .jumpToPrompt(.previous), .jumpToPrompt(.next),
    ]

    public static func verify(_ make: () -> any TerminalEngine) throws {
        unknownPaneIsIgnored(make())
        try closedPaneIsIgnored(make())
    }

    private static func unknownPaneIsIgnored(_ engine: any TerminalEngine) {
        let unknown = PaneID()
        drive(engine, unknown)
        #expect(engine.visibleText(of: unknown).isEmpty)
    }

    private static func closedPaneIsIgnored(_ engine: any TerminalEngine) throws {
        let pane = PaneID()
        // Never the login shell: against a real engine it would run the user's startup files (and their tmux).
        try engine.open(
            TerminalSessionSpec(workingDirectory: WorkingDirectory(path: "/tmp"), command: .custom("/bin/zsh -f")),
            as: pane)
        engine.close(pane)
        drive(engine, pane)
        #expect(engine.visibleText(of: pane).isEmpty)
    }

    private static func drive(_ engine: any TerminalEngine, _ pane: PaneID) {
        actions.forEach { engine.perform($0, in: pane) }
        engine.search("x", in: pane)
        engine.navigateSearch(.next, in: pane)
        engine.endSearch(in: pane)
    }
}
