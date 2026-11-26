/// What closing would end (F4.5).
public enum CloseScope: Equatable, Sendable {
    case pane
    case workspace(name: String)
    case window
    /// `windowCount`: windows with something running.
    case quit(windowCount: Int)
}

/// A pane with a process in the foreground, not at its shell prompt.
public struct BusyPane: Equatable, Sendable {
    public let pane: PaneID
    public let command: String

    public init(pane: PaneID, command: String) {
        self.pane = pane
        self.command = command
    }
}

public struct CloseQuestion: Equatable, Sendable {
    public let title: String
    public let detail: String
}

/// `[window]` in the TOML.
public struct WindowSettings: Equatable, Sendable {
    /// Ask before closing a pane, workspace or window, or quitting, while something runs.
    public var confirmClose: Bool

    public init(confirmClose: Bool) {
        self.confirmClose = confirmClose
    }

    /// F5 `[window] buttons`; outside the initializer like `SmaltiConfig.observatory`.
    public var buttons = WindowButtons.hidden

    public static let standard = WindowSettings(confirmClose: true)
}

/// Window buttons (spec F5): hidden (default), shown while the cursor is on the strip, or always visible.
public enum WindowButtons: String, CaseIterable, Sendable {
    case hidden
    case hover
    case visible

    /// The strip's left margin widens for the buttons; with `hover` it is there before they appear (Claude).
    public var reservesStripMargin: Bool { self != .hidden }
    public var isAlwaysShown: Bool { self == .visible }
    /// Shown while the cursor is on the strip, with a fade.
    public var followsCursor: Bool { self == .hover }
}

/// Decides whether closing needs the user's confirmation, and with which words.
public enum CloseGuard {
    public static func question(
        for scope: CloseScope, busy: [BusyPane], settings: WindowSettings, texts: TerminalTexts
    ) -> CloseQuestion? {
        guard settings.confirmClose, let first = busy.first else { return nil }
        switch scope {
        case .pane:
            return CloseQuestion(
                title: texts.closePane, detail: texts.closePaneDetail(["command": shortened(first.command)]))
        case .workspace(let name):
            return CloseQuestion(title: texts.closeWorkspace(["name": name]), detail: listing(busy, texts: texts))
        case .window:
            return CloseQuestion(title: texts.closeWindow, detail: listing(busy, texts: texts))
        case .quit(let windowCount):
            return CloseQuestion(title: texts.quit, detail: quitDetail(busy.count, windows: windowCount, texts: texts))
        }
    }

    /// Every busy pane of every workspace of every window, hidden ones included.
    public static func busyPanes(in windows: WindowSet, texts: TerminalTexts) -> [BusyPane] {
        busyPanes(windows.allPanes, texts: texts)
    }

    public static func busyPanes(_ panes: [Pane], texts: TerminalTexts) -> [BusyPane] {
        panes.filter(\.isBusy).map { BusyPane(pane: $0.id, command: command(of: $0, texts: texts)) }
    }

    public static func windowsWithBusyPanes(_ busy: [BusyPane], in windows: WindowSet) -> Int {
        let ids = Set(busy.map(\.pane))
        return windows.windows.count { window in window.allPanes.contains { ids.contains($0.id) } }
    }

    /// How the dialog names what runs in `pane`: its command line, else its process, else "un proceso".
    public static func command(of pane: Pane, texts: TerminalTexts) -> String {
        if let line = pane.foregroundCommandLine, !line.isEmpty { return line.joined(separator: " ") }
        return pane.processName ?? texts.aProcess
    }

    /// Commands named in a dialog, and the characters each keeps.
    static let listedCommands = 3
    static let commandLength = 40

    /// "Hay 5 procesos en marcha: job 1, job 2, job 3 y 2 más."
    private static func listing(_ busy: [BusyPane], texts: TerminalTexts) -> String {
        let named = busy.prefix(listedCommands).map { shortened($0.command) }.joined(separator: ", ")
        let rest = busy.count > listedCommands ? texts.runningRest(["count": String(busy.count - listedCommands)]) : ""
        return texts.running(["processes": texts.processes(busy.count), "named": named, "rest": rest])
    }

    private static func shortened(_ command: String) -> String {
        command.count > commandLength ? String(command.prefix(commandLength)) + "…" : command
    }

    private static func quitDetail(_ count: Int, windows: Int, texts: TerminalTexts) -> String {
        let place = windows >= 2 ? texts.inWindows(["count": String(windows)]) : ""
        return texts.quitDetail(["processes": texts.processes(count), "place": place])
    }
}
