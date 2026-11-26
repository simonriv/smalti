import SmaltiCore
import Testing

@Suite("CloseGuard")
struct CloseGuardTests {
    private let on = WindowSettings(confirmClose: true)
    private let dev = BusyPane(pane: PaneID(), command: "npm run dev")
    private let claude = BusyPane(pane: PaneID(), command: "claude")
    private let sleep = BusyPane(pane: PaneID(), command: "sleep 100")

    @Test func noBusyPanesNoQuestion() {
        #expect(CloseGuard.question(for: .pane, busy: [], settings: on, texts: .spanish) == nil)
        #expect(CloseGuard.question(for: .quit(windowCount: 2), busy: [], settings: on, texts: .spanish) == nil)
    }

    @Test func confirmCloseFalseNoQuestion() {
        #expect(
            CloseGuard.question(for: .pane, busy: [dev], settings: WindowSettings(confirmClose: false), texts: .spanish)
                == nil)
    }

    @Test func paneQuestionNamesCommand() {
        let question = CloseGuard.question(for: .pane, busy: [dev], settings: on, texts: .spanish)

        #expect(question?.title == "¿Cerrar el panel?")
        #expect(question?.detail == "npm run dev sigue en marcha. Si cierras el panel, el proceso termina.")
    }

    @Test func workspaceQuestionListsCommands() {
        let question = CloseGuard.question(
            for: .workspace(name: "solen"), busy: [dev, claude], settings: on, texts: .spanish)

        #expect(question?.title == "¿Cerrar el workspace “solen”?")
        #expect(question?.detail == "Hay 2 procesos en marcha: npm run dev, claude.")
    }

    @Test func oneProcessIsSingular() {
        let question = CloseGuard.question(for: .window, busy: [dev], settings: on, texts: .spanish)

        #expect(question?.title == "¿Cerrar la ventana?")
        #expect(question?.detail == "Hay 1 proceso en marcha: npm run dev.")
    }

    @Test func quitQuestionCountsWindows() {
        let question = CloseGuard.question(
            for: .quit(windowCount: 2), busy: [dev, claude, sleep], settings: on, texts: .spanish)

        #expect(question?.title == "¿Salir de Smalti?")
        #expect(
            question?.detail == "Hay 3 procesos en marcha en 2 ventanas. Al volver podrás retomarlos desde Reanudar.")
    }

    @Test func quitWithOneWindowLeavesWindowsOut() {
        let question = CloseGuard.question(for: .quit(windowCount: 1), busy: [dev], settings: on, texts: .spanish)

        #expect(question?.detail == "Hay 1 proceso en marcha. Al volver podrás retomarlos desde Reanudar.")
    }

    /// Review Focus 3: ⌘Q counts what runs in hidden workspaces and back windows too.
    @Test func quitCountsPanesInEveryWindowAndWorkspace() throws {
        let root = try WorkingDirectory(path: "/tmp")
        let sleeping = ForegroundProcess(name: "sleep", commandLine: ["sleep", "100"])
        let hidden = Pane(id: PaneID(), workingDirectory: root).applying(.foregroundProcessChanged(sleeping))
        let shown = Pane(id: PaneID(), workingDirectory: root)
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "zsh")))
        let back = Pane(id: PaneID(), workingDirectory: root).applying(.foregroundProcessChanged(sleeping))
        let workspaces = WorkspaceSet(
            first: .empty(name: "a", rootDirectory: root, layout: DwindleLayout()).adding(hidden)
        )
        .adding(.empty(name: "b", rootDirectory: root, layout: DwindleLayout()).adding(shown))
        let windows = WindowSet(
            first: WindowState(id: WindowID(), workspaces: workspaces, frame: nil, isFullScreen: false)
        )
        .opening(
            WindowState(
                id: WindowID(),
                workspaces: WorkspaceSet(
                    first: .empty(name: "c", rootDirectory: root, layout: DwindleLayout()).adding(back)),
                frame: nil, isFullScreen: false))

        let busy = CloseGuard.busyPanes(in: windows, texts: .spanish)

        #expect(Set(busy.map(\.pane)) == [hidden.id, back.id])
        #expect(busy.map(\.command) == ["sleep 100", "sleep 100"])
        #expect(CloseGuard.windowsWithBusyPanes(busy, in: windows) == 2)
    }

    /// Block 1 review: many panes or very long command lines keep the dialog short.
    @Test func longListsShowThreeCommandsAndHowManyMore() {
        let busy = (1...5).map { BusyPane(pane: PaneID(), command: "job \($0)") }

        let question = CloseGuard.question(for: .window, busy: busy, settings: on, texts: .spanish)

        #expect(question?.detail == "Hay 5 procesos en marcha: job 1, job 2, job 3 y 2 más.")
    }

    @Test func longCommandIsCutWithAnEllipsis() {
        let long = BusyPane(pane: PaneID(), command: "npm run dev -- --port 3000 --host 0.0.0.0 --open --verbose")

        let question = CloseGuard.question(for: .pane, busy: [long], settings: on, texts: .spanish)

        #expect(
            question?.detail
                == "npm run dev -- --port 3000 --host 0.0.0.… sigue en marcha. Si cierras el panel, el proceso termina."
        )
    }

    @Test(arguments: ["dash", "ksh", "tcsh", "csh", "nu", "xonsh", "elvish", "-ksh"])
    func otherShellsAreNotBusy(_ shell: String) throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/tmp"))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: shell)))

        #expect(!pane.isBusy)
    }

    @Test func busyPaneNamesItsForegroundCommandLine() throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/tmp"))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "npm", commandLine: ["npm", "run", "dev"])))

        #expect(CloseGuard.command(of: pane, texts: .spanish) == "npm run dev")
    }

    @Test func busyPaneWithoutCommandLineUsesTheProcessName() throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/tmp"))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "htop")))

        #expect(CloseGuard.command(of: pane, texts: .spanish) == "htop")
    }

    @Test func busyPaneWithNothingKnownSaysProceso() throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/tmp"))

        #expect(CloseGuard.command(of: pane, texts: .spanish) == "un proceso")
    }
}
