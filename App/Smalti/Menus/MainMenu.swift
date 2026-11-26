import AppKit
import SmaltiCore

/// The macOS menu bar, built from `MenuModel` (F4.5): every Smalti item shows its keymap chord and runs the same
/// `perform` as the keyboard. Each menu refreshes itself when it opens, and `refresh()` follows state changes.
@MainActor
final class MainMenu: NSObject, NSMenuDelegate {
    private let model: () -> MenuBar
    private let perform: (CommandID) -> Void
    private var menus: [MenuID: NSMenu] = [:]
    /// What the menus were last built from: an unchanged model rebuilds nothing.
    private var built: MenuBar?
    /// A menu is open: its items are not replaced under the pointer (it refreshed when it opened).
    private var openMenus = 0
    /// Built once and kept: AppKit fills it with the Services.
    private let services = NSMenu(title: String(localized: "Services"))
    /// Marks Smalti's items, so the window list AppKit adds to "Ventana" survives a refresh.
    private static let ownTag = 0xF45

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
            menus[menu.id] = submenu
        }
        NSApp.mainMenu = bar
        NSApp.servicesMenu = services
        refresh()
        NSApp.windowsMenu = menus[.window]
        NSApp.helpMenu = menus[.help]
    }

    /// Rebuilds the menus' items when the state changed what they show (chords, enabled items, checkmarks), never
    /// while one is open.
    func refresh() {
        let bar = model()
        guard openMenus == 0, bar != built else { return }
        built = bar
        for menu in bar.menus { fill(menus[menu.id], with: menu) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let current = model().menus.first(where: { menus[$0.id] === menu }) else { return }
        fill(menu, with: current)
    }

    func menuWillOpen(_ menu: NSMenu) { openMenus += 1 }

    func menuDidClose(_ menu: NSMenu) {
        openMenus = max(0, openMenus - 1)
        // What changed while it was open is applied at the next refresh.
        if openMenus == 0 { built = nil }
    }

    /// Replaces Smalti's own items (tagged), leaving what AppKit added, such as the window list, after them.
    private func fill(_ menu: NSMenu?, with model: Menu) {
        guard let menu else { return }
        menu.items.filter { $0.tag == Self.ownTag }.forEach(menu.removeItem)
        var items = model.items.map(nsItem)
        if model.id == .edit { items += dictationAndEmoji() }
        for (index, item) in items.enumerated() {
            item.tag = Self.ownTag
            menu.insertItem(item, at: index)
        }
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
        case .system(let action): return SystemMenuItems.item(item, action, services: services)
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

    private func dictationAndEmoji() -> [NSMenuItem] {
        // `startDictation:` is answered by the text system of the key view; it has no Swift-visible declaration.
        let dictation = NSMenuItem(
            title: String(localized: "Start Dictation…"), action: Selector(("startDictation:")), keyEquivalent: "")
        dictation.setAccessibilityIdentifier("smalti.menu.dictation")
        let emoji = NSMenuItem(
            title: String(localized: "Emoji & Symbols"),
            action: #selector(NSApplication.orderFrontCharacterPalette(_:)),
            keyEquivalent: "")
        emoji.setAccessibilityIdentifier("smalti.menu.emoji")
        return [.separator(), dictation, emoji]
    }
}

/// The standard items: AppKit already knows what they do.
private enum SystemMenuItems {
    @MainActor
    static func item(_ item: MenuItem, _ action: SystemMenuAction, services: NSMenu) -> NSMenuItem {
        let shortcut = item.chord.flatMap(KeyEquivalent.init)
        let nsItem = NSMenuItem(title: item.title, action: selector(action), keyEquivalent: shortcut?.key ?? "")
        nsItem.keyEquivalentModifierMask = shortcut?.modifiers ?? []
        if action == .services { nsItem.submenu = services }
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
