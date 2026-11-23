import AppKit
import SmaltiCore

/// The macOS menu bar, built from `MenuModel` (F4.5): every Smalti item shows its keymap chord and runs the same
/// `perform` as the keyboard. Each menu refreshes itself when it opens, and `refresh()` follows state changes.
@MainActor
final class MainMenu: NSObject, NSMenuDelegate {
    private let model: () -> MenuBar
    private let perform: (CommandID) -> Void
    private var menus: [String: NSMenu] = [:]

    init(model: @escaping () -> MenuBar, perform: @escaping (CommandID) -> Void) {
        self.model = model
        self.perform = perform
    }

    /// AppKit's own Dictation and Emoji items would land in a menu it recognizes by its English title; Smalti adds
    /// them itself to "Edición", once.
    func install() {
        UserDefaults.standard.register(defaults: [
            "NSDisabledDictationMenuItem": true, "NSDisabledCharacterPaletteMenuItem": true,
        ])
        let bar = NSMenu()
        for menu in model().menus {
            let top = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: menu.title)
            submenu.autoenablesItems = false
            submenu.delegate = self
            top.submenu = submenu
            bar.addItem(top)
            menus[menu.title] = submenu
        }
        NSApp.mainMenu = bar
        refresh()
        NSApp.windowsMenu = menus["Ventana"]
        NSApp.helpMenu = menus["Ayuda"]
    }

    /// Rebuilds every menu's items from the current state (chords, enabled items, checkmarks).
    func refresh() {
        for menu in model().menus { fill(menus[menu.title], with: menu.items, title: menu.title) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let current = model().menus.first(where: { $0.title == menu.title }) else { return }
        fill(menu, with: current.items, title: current.title)
    }

    private func fill(_ menu: NSMenu?, with items: [MenuItem], title: String) {
        guard let menu else { return }
        menu.removeAllItems()
        items.forEach { menu.addItem(nsItem($0)) }
        if title == "Edición" { addDictationAndEmoji(to: menu) }
    }

    private func nsItem(_ item: MenuItem) -> NSMenuItem {
        if item.isSeparator { return .separator() }
        if !item.children.isEmpty {
            let parent = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: item.title)
            submenu.autoenablesItems = false
            item.children.forEach { submenu.addItem(nsItem($0)) }
            parent.submenu = submenu
            return parent
        }
        switch item.action {
        case .command(let id): return commandItem(item, id)
        case .system(let action): return SystemMenuItems.item(item, action)
        case nil: return NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
        }
    }

    private func commandItem(_ item: MenuItem, _ id: CommandID) -> NSMenuItem {
        let shortcut = item.chord.flatMap(KeyEquivalent.init)
        let nsItem = ClosureMenuItem(title: item.title, keyEquivalent: shortcut?.key ?? "") { [weak self] in
            self?.perform(id)
        }
        nsItem.keyEquivalentModifierMask = shortcut?.modifiers ?? []
        // Smalti's chords already match by character on every layout (`KeyChord`); AppKit's own localization would
        // move them to another key (⌃⌘= showed as ⌃⌘* on the Latin American layout).
        nsItem.allowsAutomaticKeyEquivalentLocalization = false
        nsItem.isEnabled = item.isEnabled
        nsItem.state = item.isChecked ? .on : .off
        nsItem.setAccessibilityIdentifier("smalti.menu.\(id.rawValue)")
        return nsItem
    }

    private func addDictationAndEmoji(to menu: NSMenu) {
        menu.addItem(.separator())
        // `startDictation:` is answered by the text system of the key view; it has no Swift-visible declaration.
        let dictation = NSMenuItem(
            title: "Iniciar dictado…", action: Selector(("startDictation:")), keyEquivalent: "")
        dictation.setAccessibilityIdentifier("smalti.menu.dictation")
        let emoji = NSMenuItem(
            title: "Emoji y símbolos", action: #selector(NSApplication.orderFrontCharacterPalette(_:)),
            keyEquivalent: "")
        emoji.setAccessibilityIdentifier("smalti.menu.emoji")
        [dictation, emoji].forEach(menu.addItem)
    }
}

/// The standard items: AppKit already knows what they do.
private enum SystemMenuItems {
    @MainActor
    static func item(_ item: MenuItem, _ action: SystemMenuAction) -> NSMenuItem {
        let shortcut = item.chord.flatMap(KeyEquivalent.init)
        let nsItem = NSMenuItem(title: item.title, action: selector(action), keyEquivalent: shortcut?.key ?? "")
        nsItem.keyEquivalentModifierMask = shortcut?.modifiers ?? []
        if action == .services {
            let services = NSMenu(title: item.title)
            nsItem.submenu = services
            NSApp.servicesMenu = services
        }
        return nsItem
    }

    private static func selector(_ action: SystemMenuAction) -> Selector? {
        switch action {
        case .services: nil
        case .hide: #selector(NSApplication.hide(_:))
        case .hideOthers: #selector(NSApplication.hideOtherApplications(_:))
        case .showAll: #selector(NSApplication.unhideAllApplications(_:))
        case .quit: #selector(NSApplication.terminate(_:))
        case .zoom: #selector(NSWindow.performZoom(_:))
        case .bringAllToFront: #selector(NSApplication.arrangeInFront(_:))
        }
    }
}

/// A chord as AppKit's menus write it: the key's character and the modifier flags.
struct KeyEquivalent {
    let key: String
    let modifiers: NSEvent.ModifierFlags

    init?(_ chord: KeyChord) {
        guard let key = Self.character(chord.key) else { return nil }
        self.key = key
        var flags: NSEvent.ModifierFlags = []
        if chord.modifiers.contains(.command) { flags.insert(.command) }
        if chord.modifiers.contains(.option) { flags.insert(.option) }
        if chord.modifiers.contains(.control) { flags.insert(.control) }
        if chord.modifiers.contains(.shift) { flags.insert(.shift) }
        modifiers = flags
    }

    private static let named: [String: Int] = [
        "up": NSUpArrowFunctionKey, "down": NSDownArrowFunctionKey, "left": NSLeftArrowFunctionKey,
        "right": NSRightArrowFunctionKey, "pageup": NSPageUpFunctionKey, "pagedown": NSPageDownFunctionKey,
        "home": NSHomeFunctionKey, "end": NSEndFunctionKey,
    ]

    private static func character(_ key: String) -> String? {
        switch key {
        case "plus": return "+"
        case "enter": return "\r"
        case "escape": return "\u{1b}"
        case "tab": return "\t"
        default:
            if let code = named[key], let scalar = UnicodeScalar(code) { return String(Character(scalar)) }
            return key.count == 1 ? key : nil
        }
    }
}
