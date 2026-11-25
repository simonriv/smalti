/// Every shortcut and action, grouped for the help view (⌘?). Built from the keymap in effect, so a chord changed in
/// the TOML shows as changed.
public enum HelpCatalog {
    static let inPalette = "en ⌘K"

    public static func sections(keymap: Keymap) -> [HelpSection] {
        let rows = Rows(keymap: keymap)
        return [
            HelpSection(title: "Ventanas y workspaces", entries: rows.windows),
            HelpSection(title: "Paneles", entries: rows.panes),
            HelpSection(title: "Terminal", entries: rows.terminal),
            HelpSection(title: "Buscar", entries: rows.search),
            HelpSection(title: "Tiling", entries: rows.tiling),
            HelpSection(title: "Agentes y observatorio", entries: rows.agents),
            HelpSection(title: "En el prompt", entries: rows.prompt),
            HelpSection(title: "Ratón", entries: rows.mouse),
            HelpSection(title: "Configuración y ayuda", entries: rows.configuration),
        ]
    }

    /// Entries whose title fuzzy-matches `query`, or whose command id contains it; sections left empty are dropped. A
    /// blank query keeps everything.
    public static func filtered(_ sections: [HelpSection], query: String) -> [HelpSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return sections }
        return sections.compactMap { section in
            let kept = section.entries.filter {
                fuzzyScore(trimmed, in: $0.title) != nil || $0.commandName?.contains(trimmed.lowercased()) == true
            }
            return kept.isEmpty ? nil : HelpSection(title: section.title, entries: kept)
        }
    }
}

/// The rows of each section, with their chords read from one keymap.
private struct Rows {
    let keymap: Keymap

    var windows: [HelpEntry] {
        [.windowNew, .windowClose, .windowFullscreen, .windowMinimize].map(titled)
            + [
                entry(.workspaceNew, "Nuevo workspace"),
                family("Ir al workspace 1–9", NumberedShortcuts.range.map(CommandID.workspace)),
                entry(.workspaceRename, "Renombrar workspace…"), entry(.workspaceClose, "Cerrar workspace"),
                entry(.layoutImport, "Importar layout…"),
            ]
    }

    var panes: [HelpEntry] {
        [
            entry(.paneNew, "Nuevo panel"), entry(.paneClose, "Cerrar panel"),
            family("Ir al panel 1–9", NumberedShortcuts.range.map(CommandID.paneFocus)),
            family("Enfocar panel hacia…", Direction.allCases.map(CommandID.paneFocus)),
        ]
    }

    var terminal: [HelpEntry] {
        [
            .terminalCopy, .terminalPaste, .terminalSelectAll, .terminalClear, .fontIncrease, .fontDecrease, .fontReset,
            .scrollPageUp, .scrollPageDown, .scrollTop, .scrollBottom, .promptPrevious, .promptNext, .secureInputToggle,
            .previewQuickLook,
        ].map(titled)
    }

    var search: [HelpEntry] { [.searchOpen, .searchNext, .searchPrevious].map(titled) }

    var tiling: [HelpEntry] {
        LayoutCatalog.standard.all.map { entry(.layout($0.id), "Layout: \($0.displayName)") }
            + [
                entry(.panesEqualize, "Igualar paneles"),
                family("Intercambiar panel hacia…", Direction.allCases.map(CommandID.paneSwap)),
                family("Agrandar panel hacia…", Direction.allCases.map(CommandID.paneResize)),
            ]
    }

    var agents: [HelpEntry] {
        [
            entry(.agentJump, "Saltar al agente que espera"), entry(.observatoryToggle, "Abrir observatorio"),
            entry(.observatoryPeriod, "Cambiar el periodo del observatorio"),
            entry(.observatoryFilter, "Filtrar el Observatorio"),
            entry(.harnessSearch, "Buscar sesiones de agentes"),
            entry(.editorOpenBeside, "Abrir Neovim junto al agente"),
            entry(.editorOpenLastEdited, "Abrir en Neovim el último archivo editado"),
            entry(.claudeIntegrationInstall, "Instalar integración con Claude Code"),
            entry(.claudeIntegrationUninstall, "Desinstalar integración con Claude Code"),
            entry(.guardApprove, "Aprobar el comando que espera en el panel"),
            entry(.guardReject, "Rechazar el comando que espera en el panel"),
            entry(.secretsProtect, "Proteger los secretos del proyecto"),
            entry(.secretsUnprotect, "Quitar la protección de secretos del proyecto"),
        ]
    }

    /// zsh's keys in Smalti's panes (F4): not Smalti chords, so they are fixed text.
    var prompt: [HelpEntry] {
        [
            HelpEntry(title: "Completar", keys: "Tab", command: nil, covers: []),
            HelpEntry(title: "Aceptar sugerencia", keys: "→", command: nil, covers: []),
            HelpEntry(title: "Buscar en el historial", keys: "⌃R", command: .historySearch, covers: [.historySearch]),
        ]
    }

    var mouse: [HelpEntry] {
        [
            HelpEntry(title: "Abrir un enlace", keys: "⌘clic", command: nil, covers: []),
            HelpEntry(title: "Pegar la ruta de un archivo", keys: "arrastrar", command: nil, covers: []),
            HelpEntry(title: "Menú del terminal", keys: "clic derecho", command: nil, covers: []),
        ]
    }

    var configuration: [HelpEntry] {
        [entry(.paletteOpen, "Paleta de comandos")]
            + [CommandID.helpShow, .helpDocs].map(titled)
            + CommandID.appearance.map(titled)
            + [CommandID.configOpen].map(titled)
            + [entry(.configReload, "Recargar configuración")]
            + [CommandID.feedbackReport, .logsShow, .updatesCheck].map(titled)
            + [entry(.updatesAutomatic, "Activar o desactivar actualizaciones automáticas")]
            + [CommandID.appSupport, .appAbout].map(titled)
            + [
                HelpEntry(
                    title: "No preguntar al cerrar con procesos", keys: "confirm_close = false", command: nil,
                    covers: [])
            ]
    }

    private func titled(_ id: CommandID) -> HelpEntry {
        entry(id, CommandCatalog.titles[id] ?? id.rawValue)
    }

    private func entry(_ id: CommandID, _ title: String) -> HelpEntry {
        HelpEntry(
            title: title, keys: keymap.chord(for: id)?.display ?? HelpCatalog.inPalette, command: id, covers: [id])
    }

    /// One row for related commands: "⌘1…⌘9" for a numbered run, "⌥⌘←→↑↓" when every chord shares its modifiers,
    /// else each chord in turn; "en ⌘K" when none is bound.
    private func family(_ title: String, _ ids: [CommandID]) -> HelpEntry {
        HelpEntry(title: title, keys: keys(for: ids), command: nil, covers: ids)
    }

    private func keys(for ids: [CommandID]) -> String {
        let chords = ids.map(keymap.chord(for:))
        let bound = chords.compactMap { $0 }
        guard let first = bound.first else { return HelpCatalog.inPalette }
        guard bound.count == chords.count, bound.allSatisfy({ $0.modifiers == first.modifiers }) else {
            return bound.map(\.display).joined(separator: " ")
        }
        let prefix = String(first.display.dropLast(first.keySymbol.count))
        guard ids.count == NumberedShortcuts.range.count, first.key.allSatisfy(\.isNumber) else {
            return prefix + bound.map(\.keySymbol).joined()
        }
        return first.display + "…" + (bound.last?.display ?? "")
    }
}
