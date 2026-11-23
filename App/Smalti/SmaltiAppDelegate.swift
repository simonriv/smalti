import AppKit

@MainActor
final class SmaltiAppDelegate: NSObject, NSApplicationDelegate {
    private var composition: AppComposition?
    private let latencyProbe = LatencyProbe()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = AppMenu.make()
        let composition = AppComposition()
        composition.showMainWindow()
        self.composition = composition
        NSApp.activate()
        latencyProbe?.start()
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
