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
        let composition = AppComposition()
        composition.showMainWindow()
        self.composition = composition
        if AppIdentity.current.isDevelopment { NSApp.dockTile.badgeLabel = "dev" }
        NSApp.activate()
        latencyProbe?.start()
    }

    /// The session saves now; the observatory's index gets up to a second to write what it has not saved yet.
    /// F4.5: first asks, if something runs; a "Cancelar" leaves everything running.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let composition else { return .terminateNow }
        composition.confirmQuit { confirmed in
            guard confirmed else {
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            Task {
                await composition.saveForQuit()
                await composition.persistObservatory()
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    /// F4.5: "Nueva ventana" in the Dock's menu.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        composition?.dockMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// `-SmaltiExitMarker <path>` (launch argument): UI tests check this file to tell a clean quit from a crash.
    func applicationWillTerminate(_ notification: Notification) {
        latencyProbe?.finish()
        composition?.stopTelemetry()
        guard let path = UserDefaults.standard.string(forKey: "SmaltiExitMarker"), !path.isEmpty else { return }
        FileManager.default.createFile(atPath: path, contents: Data())
    }
}
