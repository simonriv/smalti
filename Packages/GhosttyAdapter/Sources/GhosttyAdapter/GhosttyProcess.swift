import Foundation
import GhosttyKit
import SmaltiCore

/// Process-wide libghostty setup. `ghostty_init` must run exactly once, before any config or app exists.
public enum GhosttyProcess {
    @MainActor private static var isInitialized = false

    /// - Parameter resourcesDirectory: the bundle's `Resources/ghostty`, so libghostty finds shell integration
    ///   and terminfo. `nil` keeps libghostty's own lookup (used by tests).
    @MainActor
    public static func ensureInitialized(resourcesDirectory: URL?) throws(TerminalEngineError) {
        guard !isInitialized else { return }
        if let resourcesDirectory {
            setenv("GHOSTTY_RESOURCES_DIR", resourcesDirectory.path(percentEncoded: false), 1)
        }
        let status = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard status == GHOSTTY_SUCCESS else {
            throw .engineStartFailed(reason: "ghostty_init returned \(status)")
        }
        isInitialized = true
    }
}
