import AppKit
import SmaltiCore

/// Composition root: the only place that builds infrastructure and wires it to the UI.
@MainActor
final class AppComposition {
    private let theme = Theme.obsidian
    private var window: SmaltiWindow?

    func showMainWindow() {
        let window = SmaltiWindow(theme: theme)
        window.makeKeyAndOrderFront(nil)
        WindowGlass.apply(blurRadius: theme.window.blurRadius, to: window)
        self.window = window
    }
}
