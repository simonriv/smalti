import Foundation
import SmaltiCore

/// Turns successive foreground process names into `foregroundProcessChanged` events, only when the name changes.
/// An unknown name (no pid, no permission) says nothing and keeps the last known one.
struct ProcessNameTracker {
    private var current: String?

    /// `commandLine` and `startedAt` are read only when the name changes (each costs a system call).
    mutating func observe(
        _ name: String?, commandLine: () -> [String]? = { nil }, pid: Int32? = nil, startedAt: () -> Date? = { nil }
    ) -> TerminalEvent? {
        guard let name, name != current else { return nil }
        current = name
        return .foregroundProcessChanged(
            SmaltiCore.ForegroundProcess(name: name, commandLine: commandLine(), pid: pid, startedAt: startedAt()))
    }
}
