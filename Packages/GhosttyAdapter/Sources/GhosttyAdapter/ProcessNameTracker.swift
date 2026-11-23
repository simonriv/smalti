import SmaltiCore

/// Turns successive foreground process names into `foregroundProcessChanged` events, only when the name changes.
/// An unknown name (no pid, no permission) says nothing and keeps the last known one.
struct ProcessNameTracker {
    private var current: String?

    mutating func observe(_ name: String?) -> TerminalEvent? {
        guard let name, name != current else { return nil }
        current = name
        return .foregroundProcessChanged(SmaltiCore.ForegroundProcess(name: name))
    }
}
