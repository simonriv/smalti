import AppKit
import SmaltiCore

/// Primary adapter for ⌘, (spec F5): the Appearance aside on the right of its window, with the panes shrunk to the
/// left and still alive. Each control's edit goes to the app's `AppearanceSession`; esc or ⌘, closes it.
@MainActor
final class AppearancePanelController: NSObject {
    var onOpenChange: ((Bool) -> Void)?
    private(set) var isOpen = false
    private let window: SmaltiWindow
    private let session: AppearanceSession
    private var view: AppearancePanelView?
    /// The swatch whose color the system color panel is editing.
    private var pickingIndex: Int?
    private var escapeMonitor: Any?

    /// UI tests: a click on a swatch picks this color instead of opening the color panel.
    private static let pickedColorKey = "SmaltiPickedColor"

    init(window: SmaltiWindow, session: AppearanceSession) {
        self.window = window
        self.session = session
    }

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        guard !isOpen else { return }
        let state = session.state
        let view = AppearancePanelView(theme: state.applied.theme)
        view.onEdit = { [weak self] edit in self?.perform(edit) }
        view.onClose = { [weak self] in self?.close() }
        window.showSidePanel(view, width: state.applied.theme.appearancePanel.width)
        view.render(state)
        self.view = view
        isOpen = true
        window.makeFirstResponder(view.firstControl)
        // Esc closes while the keyboard is in the panel; in a pane (still alive beside it) it reaches the terminal.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            let isOurs = event.window === self?.window
            // Local monitors run on the main thread.
            let closed = MainActor.assumeIsolated { () -> Bool in
                guard let self, isOurs, self.ownsKeyboard else { return false }
                self.close()
                return true
            }
            return closed ? nil : event
        }
        onOpenChange?(true)
    }

    private static let escapeKeyCode: UInt16 = 53

    /// The keyboard is on one of the panel's controls: publishes must not hand it back to a terminal.
    var ownsKeyboard: Bool {
        guard let view, let responder = window.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: view)
    }

    func close() {
        guard isOpen else { return }
        window.showSidePanel(nil, width: 0)
        view = nil
        isOpen = false
        escapeMonitor.map(NSEvent.removeMonitor)
        escapeMonitor = nil
        if pickingIndex != nil {
            NSColorPanel.shared.setTarget(nil)
            NSColorPanel.shared.setAction(nil)
        }
        pickingIndex = nil
        onOpenChange?(false)
    }

    /// The document changed (an edit here, in another window, or "Recargar configuración").
    func refresh() {
        view?.render(session.state)
    }

    private func perform(_ edit: AppearanceEdit) {
        switch edit {
        case .theme(let id): session.selectTheme(id)
        case .glassOpacity(let value): session.edit { $0.appearance.glassOpacity = value }
        case .blur(let value): session.edit { $0.appearance.blur = value }
        case .protectLegibility(let isOn): session.edit { $0.appearance.protectLegibility = isOn }
        case .pickANSI(let index): pickColor(for: index)
        case .buttons(let mode): session.edit { $0.buttons = mode }
        case .fontFamily(let family): session.edit { $0.appearance.fontFamily = family }
        case .fontSize(let size): session.edit { $0.appearance.fontSize = size }
        case .gap(let gap): session.edit { $0.appearance.gap = gap }
        case .radius(let radius): session.edit { $0.appearance.radius = radius }
        }
    }

    // MARK: - ANSI colors

    private func pickColor(for index: Int) {
        if let hex = UserDefaults.standard.string(forKey: Self.pickedColorKey), let color = try? RGBAColor(hex: hex) {
            setANSI(index, color)
            return
        }
        pickingIndex = index
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPicked(_:)))
        panel.isContinuous = true
        panel.showsAlpha = false
        panel.orderFront(nil)
    }

    @objc private func colorPicked(_ panel: NSColorPanel) {
        guard let index = pickingIndex, let srgb = panel.color.usingColorSpace(.sRGB) else { return }
        let color = RGBAColor(
            red: UInt8((srgb.redComponent * 255).rounded()), green: UInt8((srgb.greenComponent * 255).rounded()),
            blue: UInt8((srgb.blueComponent * 255).rounded()), alpha: 1)
        setANSI(index, color)
    }

    private func setANSI(_ index: Int, _ color: RGBAColor) {
        // The swatches are 0–15, the range `setANSI` accepts.
        session.edit { try? $0.setANSI(index, to: color) }
    }
}
