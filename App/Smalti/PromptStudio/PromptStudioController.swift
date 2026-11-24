import AppKit
import CoreText
import SmaltiCore

/// Primary adapter for ⇧⌘P (spec F5): the prompt studio over its window. It edits `EditPrompt`'s draft; "Aplicar a
/// todos los paneles" goes through the app's `AppearanceSession`, and the export writes `starship.toml`.
@MainActor
final class PromptStudioController {
    var onOpenChange: ((Bool) -> Void)?
    private(set) var isOpen = false
    private let window: SmaltiWindow
    private let session: AppearanceSession
    private var editor: EditPrompt?
    private var view: PromptStudioView?
    private var escapeMonitor: Any?
    /// Looked up once per opening (block 5 review, M9).
    private var hasNerdFont = false
    /// ⌘K or the help open on top of the studio: their Esc is theirs (block 5 review, M3).
    var hasOverlayOnTop: () -> Bool = { false }

    /// UI tests: where the export writes, without the save panel.
    private static let exportDirectoryKey = "SmaltiExportDirectory"
    /// UI tests: whether a Nerd Font counts as installed.
    private static let nerdFontKey = "SmaltiNerdFontAvailable"
    private static let escapeKeyCode: UInt16 = 53
    private static let exportName = "starship.toml"

    init(window: SmaltiWindow, session: AppearanceSession) {
        self.window = window
        self.session = session
    }

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        guard !isOpen, let content = window.contentView else { return }
        let editor = session.promptEditor()
        let view = PromptStudioView(theme: session.theme)
        view.onEdit = { [weak self] edit in self?.perform(edit) }
        content.addSubview(view, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        self.editor = editor
        self.view = view
        isOpen = true
        hasNerdFont = Self.isNerdFontInstalled
        render()
        window.makeFirstResponder(view.firstControl)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            let isOurs = event.window === self?.window
            // Local monitors run on the main thread.
            let closed = MainActor.assumeIsolated { () -> Bool in
                guard let self, isOurs, self.isOpen, !self.hasOverlayOnTop() else { return false }
                self.close()
                return true
            }
            return closed ? nil : event
        }
        onOpenChange?(true)
    }

    func close() {
        guard isOpen else { return }
        view?.removeFromSuperview()
        view = nil
        editor = nil
        isOpen = false
        escapeMonitor.map(NSEvent.removeMonitor)
        escapeMonitor = nil
        onOpenChange?(false)
    }

    /// ⌘K's "Aplicar prompt a todos los paneles" and "Exportar como starship.toml" while the studio is open.
    func perform(_ edit: PromptStudioEdit) {
        guard let editor else { return }
        switch edit {
        case .template(let template): editor.draft = editor.draft.applying(template)
        case .toggle(let id): editor.toggle(id)
        case .move(let id, let offset): editor.move(id, by: offset)
        case .icons(let icons): editor.draft.icons = icons
        case .symbol(let symbol): editor.draft.symbol = symbol
        case .toggleLayout: editor.draft.layout = editor.draft.layout == .twoLines ? .oneLine : .twoLines
        case .toggleShellPrompt: editor.draft.source = editor.draft.source == .shell ? .smalti : .shell
        case .apply: session.applyPrompt(editor)
        case .export: export(editor.draft)
        }
        render()
    }

    private func render() {
        guard let editor, let view else { return }
        let previews = PreviewSituation.allCases.map { (title: $0.title, lines: editor.preview($0)) }
        view.render(
            PromptStudioState(
                draft: editor.draft, previews: previews, moduleList: editor.moduleList, theme: session.theme,
                hasNerdFont: hasNerdFont))
    }

    // MARK: - Export

    private func export(_ draft: PromptConfig) {
        let text = session.starshipText(for: draft)
        if let folder = UserDefaults.standard.string(forKey: Self.exportDirectoryKey), !folder.isEmpty {
            write(text, to: URL(filePath: folder).appending(path: Self.exportName))
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.exportName
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config")
        // The panel itself asks before replacing an existing file.
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.write(text, to: url) }
        }
    }

    /// A `starship.toml` linked from dotfiles is written through its link (block 5 review, M4).
    private func write(_ text: String, to chosen: URL) {
        let url = chosen.resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).beginSheetModal(for: window)
        }
    }

    // MARK: - Nerd Font

    /// A font whose name says Nerd Font is installed (`CTFontManager`); `-SmaltiNerdFontAvailable` overrides it.
    private static var isNerdFontInstalled: Bool {
        if UserDefaults.standard.object(forKey: nerdFontKey) != nil {
            return UserDefaults.standard.bool(forKey: nerdFontKey)
        }
        let families = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return families.contains { $0.localizedCaseInsensitiveContains("Nerd Font") }
    }
}
