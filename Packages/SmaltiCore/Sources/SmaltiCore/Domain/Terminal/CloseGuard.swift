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

    public static let standard = WindowSettings(confirmClose: true)
}

/// Decides whether closing needs the user's confirmation, and with which words.
public enum CloseGuard {
    public static func question(for scope: CloseScope, busy: [BusyPane], settings: WindowSettings) -> CloseQuestion? {
        guard settings.confirmClose, let first = busy.first else { return nil }
        switch scope {
        case .pane:
            return CloseQuestion(
                title: "¿Cerrar el panel?",
                detail: "\(shortened(first.command)) sigue en marcha. Si cierras el panel, el proceso termina.")
        case .workspace(let name):
            return CloseQuestion(title: "¿Cerrar el workspace “\(name)”?", detail: listing(busy))
        case .window:
            return CloseQuestion(title: "¿Cerrar la ventana?", detail: listing(busy))
        case .quit(let windowCount):
            return CloseQuestion(title: "¿Salir de Smalti?", detail: quitDetail(busy.count, windows: windowCount))
        }
    }

    /// Every busy pane of every workspace of every window, hidden ones included.
    public static func busyPanes(in windows: WindowSet) -> [BusyPane] {
        busyPanes(windows.allPanes)
    }

    public static func busyPanes(_ panes: [Pane]) -> [BusyPane] {
        panes.filter(\.isBusy).map { BusyPane(pane: $0.id, command: command(of: $0)) }
    }

    public static func windowsWithBusyPanes(_ busy: [BusyPane], in windows: WindowSet) -> Int {
        let ids = Set(busy.map(\.pane))
        return windows.windows.count { window in window.allPanes.contains { ids.contains($0.id) } }
    }

    /// How the dialog names what runs in `pane`: its command line, else its process, else "un proceso".
    public static func command(of pane: Pane) -> String {
        if let line = pane.foregroundCommandLine, !line.isEmpty { return line.joined(separator: " ") }
        return pane.processName ?? "un proceso"
    }

    /// Commands named in a dialog, and the characters each keeps.
    static let listedCommands = 3
    static let commandLength = 40

    /// "Hay 5 procesos en marcha: job 1, job 2, job 3 y 2 más."
    private static func listing(_ busy: [BusyPane]) -> String {
        let named = busy.prefix(listedCommands).map { shortened($0.command) }.joined(separator: ", ")
        let rest = busy.count > listedCommands ? " y \(busy.count - listedCommands) más" : ""
        return "Hay \(processes(busy.count)) en marcha: \(named)\(rest)."
    }

    private static func shortened(_ command: String) -> String {
        command.count > commandLength ? String(command.prefix(commandLength)) + "…" : command
    }

    private static func quitDetail(_ count: Int, windows: Int) -> String {
        let place = windows >= 2 ? " en \(windows) ventanas" : ""
        return "Hay \(processes(count)) en marcha\(place). Al volver podrás retomarlos desde Reanudar."
    }

    private static func processes(_ count: Int) -> String {
        count == 1 ? "1 proceso" : "\(count) procesos"
    }
}
