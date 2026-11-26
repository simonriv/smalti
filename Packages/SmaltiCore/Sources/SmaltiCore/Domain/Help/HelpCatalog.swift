/// Every shortcut and action, grouped for the help view (⌘?). Built from the keymap in effect, so a chord changed in
/// the TOML shows as changed.
public enum HelpCatalog {
    public static func sections(keymap: Keymap, texts: HelpTexts) -> [HelpSection] {
        let rows = Rows(keymap: keymap, texts: texts)
        return HelpSectionID.allCases.map { HelpSection(title: texts.sections[$0] ?? "", entries: rows.entries($0)) }
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
    let texts: HelpTexts

    func entries(_ section: HelpSectionID) -> [HelpEntry] {
        switch section {
        case .windows: windows
        case .panes: panes
        case .terminal: terminal
        case .search: search
        case .tiling: tiling
        case .agents: agents
        case .processes: CommandID.processes.map(titled)
        case .prompt: prompt
        case .mouse: mouse
        case .configuration: configuration
        case .privacy: privacy
        }
    }

    var windows: [HelpEntry] {
        [CommandID.windowNew, .windowClose, .windowFullscreen, .windowMinimize, .workspaceNew].map(titled)
            + [family(texts.goToWorkspaces, NumberedShortcuts.range.map(CommandID.workspace))]
            + [CommandID.workspaceRename, .workspaceClose, .layoutImport, .projectRecent, .projectSave].map(titled)
    }

    var panes: [HelpEntry] {
        [CommandID.paneNew, .paneClose].map(titled)
            + [
                family(texts.goToPanes, NumberedShortcuts.range.map(CommandID.paneFocus)),
                family(texts.focusPanes, Direction.allCases.map(CommandID.paneFocus)),
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
        let commands = texts.commands
        return LayoutCatalog.standard.all.map {
            entry(.layout($0.id), commands.layoutTitle(["name": commands.layoutNames[$0.id] ?? $0.id.rawValue]))
        }
            + [
                titled(.panesEqualize),
                family(texts.swapPanes, Direction.allCases.map(CommandID.paneSwap)),
                family(texts.resizePanes, Direction.allCases.map(CommandID.paneResize)),
            ]
    }

    var agents: [HelpEntry] {
        [
            CommandID.agentJump, .observatoryToggle, .observatoryPeriod, .observatoryFilter, .harnessSearch,
            .timelineToggle, .timelineSearch, .timelineCopy, .timelineCopyCall, .editorOpenBeside,
            .editorOpenLastEdited, .claudeIntegrationInstall, .claudeIntegrationUninstall,
            .guardApprove, .guardReject, .secretsProtect, .secretsUnprotect,
        ].map(titled)
    }

    /// zsh's keys in Smalti's panes (F4): not Smalti chords, so they are fixed text.
    var prompt: [HelpEntry] {
        [
            HelpEntry(title: texts.complete, keys: "Tab", command: nil, covers: []),
            HelpEntry(title: texts.acceptSuggestion, keys: "→", command: nil, covers: []),
            HelpEntry(title: texts.searchHistory, keys: "⌃R", command: .historySearch, covers: [.historySearch]),
        ]
    }

    var mouse: [HelpEntry] {
        [
            HelpEntry(title: texts.openLink, keys: texts.openLinkKeys, command: nil, covers: []),
            HelpEntry(title: texts.pastePath, keys: texts.pastePathKeys, command: nil, covers: []),
            HelpEntry(title: texts.terminalMenu, keys: texts.terminalMenuKeys, command: nil, covers: []),
        ]
    }

    var configuration: [HelpEntry] {
        [CommandID.paletteOpen, .helpShow, .helpWelcome, .helpDocs].map(titled)
            + CommandID.appearance.map(titled)
            + [
                CommandID.configOpen, .configReload, .feedbackReport, .logsShow, .updatesCheck, .updatesAutomatic,
                .appSupport, .appAbout,
            ].map(titled)
            + [HelpEntry(title: texts.confirmClose, keys: "confirm_close = false", command: nil, covers: [])]
    }

    /// F7.7: what leaves the Mac, as text rows, then the full policy on the web.
    var privacy: [HelpEntry] {
        texts.privacyLines.map { HelpEntry(title: $0, keys: "", command: nil, covers: []) } + [titled(.helpPrivacy)]
    }

    /// "en ⌘K", naming the palette's chord in effect.
    private var inPalette: String {
        texts.inPalette(["palette": WelcomeContent.palette(keymap)])
    }

    private func titled(_ id: CommandID) -> HelpEntry {
        entry(id, texts.titles[id] ?? texts.commands.titles[id] ?? texts.commands.paletteTitles[id] ?? id.rawValue)
    }

    private func entry(_ id: CommandID, _ title: String) -> HelpEntry {
        HelpEntry(title: title, keys: keymap.chord(for: id)?.display ?? inPalette, command: id, covers: [id])
    }

    /// One row for related commands: "⌘1…⌘9" for a numbered run, "⌥⌘←→↑↓" when every chord shares its modifiers,
    /// else each chord in turn; "en ⌘K" when none is bound.
    private func family(_ title: String, _ ids: [CommandID]) -> HelpEntry {
        HelpEntry(title: title, keys: keys(for: ids), command: nil, covers: ids)
    }

    private func keys(for ids: [CommandID]) -> String {
        let chords = ids.map(keymap.chord(for:))
        let bound = chords.compactMap { $0 }
        guard let first = bound.first else { return inPalette }
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
