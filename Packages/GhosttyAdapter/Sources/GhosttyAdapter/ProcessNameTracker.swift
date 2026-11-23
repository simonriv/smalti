import SmaltiCore

/// Turns successive foreground process names into `foregroundProcessChanged` events, only when the name changes.
/// An unknown name (no pid, no permission) says nothing and keeps the last known one.
struct ProcessNameTracker {
    private var current: String?

    /// `commandLine` is read only when the name changes (it costs a `sysctl`).
    mutating func observe(_ name: String?, commandLine: () -> [String]? = { nil }) -> TerminalEvent? {
        guard let name, name != current else { return nil }
        current = name
        return .foregroundProcessChanged(SmaltiCore.ForegroundProcess(name: name, commandLine: commandLine()))
    }
}
