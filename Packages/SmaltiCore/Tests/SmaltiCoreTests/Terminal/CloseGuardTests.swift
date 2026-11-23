import SmaltiCore
import Testing

@Suite("CloseGuard")
struct CloseGuardTests {
    private let on = WindowSettings(confirmClose: true)
    private let dev = BusyPane(pane: PaneID(), command: "npm run dev")
    private let claude = BusyPane(pane: PaneID(), command: "claude")
    private let sleep = BusyPane(pane: PaneID(), command: "sleep 100")

    @Test func noBusyPanesNoQuestion() {
        #expect(CloseGuard.question(for: .pane, busy: [], settings: on) == nil)
        #expect(CloseGuard.question(for: .quit(windowCount: 2), busy: [], settings: on) == nil)
    }

    @Test func confirmCloseFalseNoQuestion() {
        #expect(CloseGuard.question(for: .pane, busy: [dev], settings: WindowSettings(confirmClose: false)) == nil)
    }

    @Test func paneQuestionNamesCommand() {
        let question = CloseGuard.question(for: .pane, busy: [dev], settings: on)

        #expect(question?.title == "¿Cerrar el panel?")
        #expect(question?.detail == "npm run dev sigue en marcha. Si cierras el panel, el proceso termina.")
    }

    @Test func workspaceQuestionListsCommands() {
        let question = CloseGuard.question(for: .workspace(name: "solen"), busy: [dev, claude], settings: on)

        #expect(question?.title == "¿Cerrar el workspace “solen”?")
        #expect(question?.detail == "Hay 2 procesos en marcha: npm run dev, claude.")
    }

    @Test func oneProcessIsSingular() {
        let question = CloseGuard.question(for: .window, busy: [dev], settings: on)

        #expect(question?.title == "¿Cerrar la ventana?")
        #expect(question?.detail == "Hay 1 proceso en marcha: npm run dev.")
    }

    @Test func quitQuestionCountsWindows() {
        let question = CloseGuard.question(for: .quit(windowCount: 2), busy: [dev, claude, sleep], settings: on)

        #expect(question?.title == "¿Salir de Smalti?")
        #expect(
            question?.detail == "Hay 3 procesos en marcha en 2 ventanas. Al volver podrás retomarlos desde Reanudar.")
    }

    @Test func quitWithOneWindowLeavesWindowsOut() {
        let question = CloseGuard.question(for: .quit(windowCount: 1), busy: [dev], settings: on)

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

        let busy = CloseGuard.busyPanes(in: windows)

        #expect(Set(busy.map(\.pane)) == [hidden.id, back.id])
        #expect(busy.map(\.command) == ["sleep 100", "sleep 100"])
        #expect(CloseGuard.windowsWithBusyPanes(busy, in: windows) == 2)
    }

    @Test func busyPaneNamesItsForegroundCommandLine() throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/tmp"))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "npm", commandLine: ["npm", "run", "dev"])))

        #expect(CloseGuard.command(of: pane) == "npm run dev")
    }

    @Test func busyPaneWithoutCommandLineUsesTheProcessName() throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/tmp"))
            .applying(.foregroundProcessChanged(ForegroundProcess(name: "htop")))

        #expect(CloseGuard.command(of: pane) == "htop")
    }

    @Test func busyPaneWithNothingKnownSaysProceso() throws {
        let pane = Pane(id: PaneID(), workingDirectory: try WorkingDirectory(path: "/tmp"))

        #expect(CloseGuard.command(of: pane) == "un proceso")
    }
}
