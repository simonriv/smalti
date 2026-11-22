import AppKit

/// Minimal app menu: Smalti has no fixed buttons, but macOS still needs Quit and Hide.
enum AppMenu {
    @MainActor
    static func make() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ocultar Smalti", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Salir de Smalti", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        return menu
    }
}
