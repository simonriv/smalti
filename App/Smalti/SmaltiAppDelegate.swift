import AppKit

@MainActor
final class SmaltiAppDelegate: NSObject, NSApplicationDelegate {
    private var composition: AppComposition?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = AppMenu.make()
        let composition = AppComposition()
        composition.showMainWindow()
        self.composition = composition
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
