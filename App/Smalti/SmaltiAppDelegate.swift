import AppKit
import SmaltiCore

@MainActor
final class SmaltiAppDelegate: NSObject, NSApplicationDelegate {
    private var composition: AppComposition?
    private let latencyProbe = LatencyProbe()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before any pane starts: panes inherit this process's environment.
        for name in InheritedEnvironment.agentSessionVariables(in: ProcessInfo.processInfo.environment) {
            unsetenv(name)
        }
        NSApp.mainMenu = AppMenu.make()
        let composition = AppComposition()
        composition.showMainWindow()
        self.composition = composition
        if AppIdentity.current.isDevelopment { NSApp.dockTile.badgeLabel = "dev" }
        NSApp.activate()
        latencyProbe?.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        composition?.saveForQuit()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// `-SmaltiExitMarker <path>` (launch argument): UI tests check this file to tell a clean quit from a crash.
    func applicationWillTerminate(_ notification: Notification) {
        latencyProbe?.finish()
        guard let path = UserDefaults.standard.string(forKey: "SmaltiExitMarker"), !path.isEmpty else { return }
        FileManager.default.createFile(atPath: path, contents: Data())
    }
}
