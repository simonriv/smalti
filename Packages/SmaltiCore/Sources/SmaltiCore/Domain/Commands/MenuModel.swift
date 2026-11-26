/// What a macOS menu item does: one of Smalti's commands, or one AppKit already knows.
public enum MenuAction: Equatable, Sendable {
    case command(CommandID)
    case system(SystemMenuAction)
}

/// Standard items whose behavior AppKit provides; the app maps each to its selector.
public enum SystemMenuAction: Hashable, Sendable {
    case services, hide, hideOthers, showAll, quit, zoom, bringAllToFront
}

/// One item of the menu bar, the terminal's context menu or the Dock menu. A separator has no title and no action.
public struct MenuItem: Equatable, Sendable {
    public let title: String
    public let action: MenuAction?
    public let chord: KeyChord?
    public let isEnabled: Bool
    public let children: [MenuItem]
    /// Shown with a ✓ ("Entrada de teclado segura" while it is on).
    public var isChecked = false

    public init(title: String, action: MenuAction?, chord: KeyChord?, isEnabled: Bool, children: [MenuItem]) {
        self.title = title
        self.action = action
        self.chord = chord
        self.isEnabled = isEnabled
        self.children = children
    }

    public static let separator = MenuItem(title: "", action: nil, chord: nil, isEnabled: false, children: [])

    public var isSeparator: Bool { title.isEmpty && action == nil && children.isEmpty }

    public var command: CommandID? {
        if case .command(let id) = action { id } else { nil }
    }

    static func submenu(_ title: String, _ children: [MenuItem]) -> MenuItem {
        MenuItem(title: title, action: nil, chord: nil, isEnabled: true, children: children)
    }
}

extension [MenuItem] {
    /// Every item, submenus' included, depth first.
    public var flattened: [MenuItem] { flatMap { [$0] + $0.children.flattened } }
}

/// Which menu of the bar: the app finds Edición, Ventana and Ayuda by this, never by their titles.
public enum MenuID: Hashable, Sendable {
    case app, file, edit, view, window, help
}

public struct Menu: Equatable, Sendable {
    public let id: MenuID
    public let title: String
    public let items: [MenuItem]
}

public struct MenuBar: Equatable, Sendable {
    public let menus: [Menu]

    public init(menus: [Menu]) {
        self.menus = menus
    }

    /// No menus yet (before the first window exists).
    public static let empty = MenuBar(menus: [])
}

/// What the menus reflect besides the keymap: the front window's workspaces, the toggles that are on, and what its
/// keyboard allows right now (an overlay, the resume screen): the menu never does what the keys would not.
public struct MenuState: Sendable {
    public let workspaces: WorkspaceSet
    public let checked: Set<CommandID>
    public let context: KeyContext

    public init(workspaces: WorkspaceSet, checked: Set<CommandID>, context: KeyContext = .unrestricted) {
        self.workspaces = workspaces
        self.checked = checked
        self.context = context
    }
}

/// The menus of macOS (F4.5), built from the keymap in effect and the palette's commands for the current state: an
/// item shows its command's primary chord and is enabled when ⌘K would offer it.
public enum MenuModel {
    public static func bar(keymap: Keymap, commands: [Command], state: MenuState, texts: MenuTexts) -> MenuBar {
        let context = state.context
        let offered = Set(commands.map(\.id)).union(alwaysAvailable).filter {
            context.allowing?.contains($0) ?? true
        }
        let builder = Builder(
            keymap: keymap, available: offered.subtracting(context.passingThrough), checked: state.checked,
            texts: texts, offeredTitles: Dictionary(commands.map { ($0.id, $0.title) }) { first, _ in first })
        let workspaces = state.workspaces
        let menus: [(MenuID, [MenuItem])] = [
            (.app, builder.app), (.file, builder.file), (.edit, builder.edit), (.view, builder.view),
            (.window, builder.window(workspaces)), (.help, builder.help),
        ]
        return MenuBar(menus: menus.map { Menu(id: $0.0, title: texts.menus[$0.0] ?? "", items: $0.1) })
    }

    public static func contextMenu(keymap: Keymap, texts: MenuTexts) -> [MenuItem] {
        let builder = Builder(keymap: keymap, available: nil, checked: [], texts: texts)
        return [
            builder.item(.terminalCopy), builder.item(.terminalPaste), builder.item(.terminalSelectAll), .separator,
            builder.item(.searchOpen), builder.item(.terminalClear), .separator, builder.item(.paneNew),
            builder.item(.paneClose),
        ]
    }

    public static func dockMenu(texts: MenuTexts) -> [MenuItem] {
        [Builder(keymap: .standard, available: nil, checked: [], texts: texts).item(.windowNew, chord: nil)]
    }

    /// Commands the palette does not list but that always apply.
    static let alwaysAvailable: Set<CommandID> = [.paletteOpen, .observatoryToggle]
}

private struct Builder {
    let keymap: Keymap
    /// nil: everything is enabled (the context menu acts on the pane it was opened on).
    let available: Set<CommandID>?
    let checked: Set<CommandID>
    let texts: MenuTexts
    /// The palette's titles, for items whose title depends on the state (F7.6: the automatic-updates toggle).
    var offeredTitles: [CommandID: String] = [:]

    func item(_ id: CommandID, title: String? = nil) -> MenuItem {
        item(id, chord: keymap.chord(for: id), title: title)
    }

    func item(_ id: CommandID, chord: KeyChord?, title: String? = nil) -> MenuItem {
        var item = MenuItem(
            title: title ?? texts.titles[id] ?? texts.commands.titles[id] ?? offeredTitles[id] ?? id.rawValue,
            action: .command(id), chord: chord,
            isEnabled: available?.contains(id) ?? true, children: [])
        item.isChecked = checked.contains(id)
        return item
    }

    /// A chord the TOML gave to one of Smalti's commands is that command's: the system item shows none.
    private func system(_ action: SystemMenuAction, _ chord: String? = nil) -> MenuItem {
        let parsed = chord.flatMap { try? KeyChord.parse($0) }
        let free = parsed.flatMap { keymap.command(for: $0) == nil ? $0 : nil }
        return MenuItem(
            title: texts.system[action] ?? "", action: .system(action), chord: free, isEnabled: true, children: [])
    }

    var app: [MenuItem] {
        [
            item(.appAbout)
        ] + updateItems + [
            .separator, item(.appearanceOpen), item(.promptStudio), item(.configOpen),
            item(.configReload), .separator, item(.secureInputToggle),
            .separator, system(.services), .separator, system(.hide, "cmd+h"), system(.hideOthers, "cmd+opt+h"),
            system(.showAll), .separator, system(.quit, "cmd+q"),
        ]
    }

    /// F7.6: only when the palette offers them (a build that can update itself).
    private var updateItems: [MenuItem] {
        [CommandID.updatesCheck, .updatesAutomatic].filter { offeredTitles[$0] != nil }.map { item($0) }
    }

    var file: [MenuItem] {
        [
            item(.windowNew), item(.paneNew), item(.workspaceNew), .separator, item(.paneClose), item(.workspaceClose),
            item(.windowClose),
        ]
    }

    var edit: [MenuItem] {
        [
            item(.terminalCopy), item(.terminalPaste), item(.terminalSelectAll), .separator, item(.searchOpen),
            item(.searchNext), item(.searchPrevious), .separator, item(.terminalClear), item(.historySearch),
        ]
    }

    var view: [MenuItem] {
        let layouts = LayoutCatalog.standard.all.map {
            item(.layout($0.id), title: texts.commands.layoutNames[$0.id] ?? $0.id.rawValue)
        }
        let scrolling = [
            CommandID.scrollPageUp, .scrollPageDown, .scrollTop, .scrollBottom, .promptPrevious, .promptNext,
        ]
        return [
            item(.paletteOpen), item(.observatoryToggle), item(.observatoryFilter), item(.harnessSearch),
            item(.layoutImport),
            .separator,
        ] + CommandID.processes.map { item($0) } + [
            .separator,
            .submenu(texts.layoutSubmenu, layouts), item(.panesEqualize),
            .separator, item(.fontIncrease), item(.fontDecrease), item(.fontReset), .separator,
            .submenu(texts.scrollingSubmenu, scrolling.map { item($0) }), item(.previewQuickLook),
            item(.editorOpenBeside),
            item(.editorOpenLastEdited), .separator, item(.windowFullscreen),
        ]
    }

    func window(_ workspaces: WorkspaceSet) -> [MenuItem] {
        [
            item(.windowMinimize), system(.zoom), .separator,
            .submenu(texts.paneSubmenu, numberedPanes(workspaces.active) + [.separator] + paneItems), item(.agentJump),
            item(.guardApprove), item(.guardReject),
            .separator, .submenu(texts.workspaceSubmenu, workspaceItems(workspaces)), .separator,
            system(.bringAllToFront),
        ]
    }

    var help: [MenuItem] {
        [
            item(.helpShow), item(.helpWelcome), item(.helpDocs), item(.helpPrivacy), .separator,
            item(.feedbackReport), item(.logsShow), .separator,
            item(.appSupport),
        ]
    }

    private var paneItems: [MenuItem] {
        let families: [(template: TextTemplate, id: (Direction) -> CommandID)] = [
            (texts.focusToward, CommandID.paneFocus), (texts.swapToward, CommandID.paneSwap),
            (texts.resizeToward, CommandID.paneResize),
        ]
        let groups = families.map { family in
            Direction.allCases.map {
                item(family.id($0), title: family.template(["direction": texts.directions[$0] ?? ""]))
            }
        }
        return groups.dropFirst().reduce(groups[0]) { $0 + [.separator] + $1 }
    }

    /// "Panel 1 · zsh": the active workspace's numbered panes.
    private func numberedPanes(_ workspace: Workspace) -> [MenuItem] {
        workspace.panes.prefix(NumberedShortcuts.range.upperBound).enumerated().map { index, pane in
            let name = pane.headerName
            let number = String(index + 1)
            let title =
                name.isEmpty ? texts.pane(["number": number]) : texts.namedPane(["number": number, "name": name])
            return item(.paneFocus(index + 1), title: title)
        }
    }

    private func workspaceItems(_ workspaces: WorkspaceSet) -> [MenuItem] {
        let numbered = workspaces.workspaces.prefix(NumberedShortcuts.range.upperBound).enumerated().map {
            index, workspace in
            MenuItem(
                title: workspace.name, action: .command(.workspace(index + 1)),
                chord: keymap.chord(for: .workspace(index + 1)), isEnabled: true, children: [])
        }
        return numbered + [.separator, item(.workspaceRename)]
    }
}
