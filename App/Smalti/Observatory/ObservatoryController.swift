import AppKit
import SmaltiCore

/// Primary adapter for ⌘⇧A: shows the observatory over the whole window, keeps its period and selection, and turns
/// ↑↓, ↵ and esc into moves, a jump to the session's pane, and closing. It holds no observatory rules: the report
/// comes from the domain.
@MainActor
final class ObservatoryController {
    struct Actions {
        /// The panes stay alive underneath; hiding them is the window's business.
        let setTilingHidden: (Bool) -> Void
        /// After closing: focus this pane (↵ on a session) or the one focused before (nil).
        let didClose: (PaneID?) -> Void
        let openChanged: (Bool) -> Void
    }

    private let window: NSWindow
    private let actions: Actions
    private var view: ObservatoryView?
    private var theme: Theme?
    private var snapshot: ObservatorySnapshot?
    private var report: ObservatoryReport?
    private(set) var period = ObservatoryPeriod.today
    private var selection: String?

    var isOpen: Bool { view != nil }

    init(window: NSWindow, actions: Actions) {
        self.window = window
        self.actions = actions
    }

    func toggle(theme: Theme) {
        isOpen ? close(focusing: nil) : open(theme: theme)
    }

    func cyclePeriod() {
        guard isOpen else { return }
        period = period.next
        render()
    }

    /// The refresher's latest facts; drawn right away while the observatory is open.
    func show(_ snapshot: ObservatorySnapshot) {
        self.snapshot = snapshot
        if isOpen { render() }
    }

    private func open(theme: Theme) {
        guard let content = window.contentView else { return }
        let view = ObservatoryView(theme: theme)
        view.frame = content.bounds
        view.autoresizingMask = [.width, .height]
        view.onSelect = { [weak self] id in self?.select(id) }
        view.onCyclePeriod = { [weak self] in self?.cyclePeriod() }
        view.onKey = { [weak self] key in self?.handle(key) }
        self.view = view
        self.theme = theme
        content.addSubview(view)
        actions.setTilingHidden(true)
        fade(view, to: 1, from: 0)
        window.makeFirstResponder(view)
        render()
        actions.openChanged(true)
    }

    private func close(focusing pane: PaneID?) {
        guard let view else { return }
        self.view = nil
        view.removeFromSuperview()
        actions.setTilingHidden(false)
        actions.openChanged(false)
        actions.didClose(pane)
    }

    private func render() {
        guard let view, let snapshot else { return }
        let report = ObservatoryReport.make(
            snapshot, period: period, selection: selection, calendar: .autoupdatingCurrent)
        self.report = report
        selection = report.detail?.sessionID
        view.show(report, snapshot: snapshot, period: period)
    }

    private func select(_ id: String) {
        selection = id
        render()
    }

    private func handle(_ key: ObservatoryView.Key) {
        switch key {
        case .up: move(by: -1)
        case .down: move(by: 1)
        case .open:
            guard let pane = report?.rows.first(where: { $0.id == selection })?.pane else { return }
            close(focusing: pane)
        case .close: close(focusing: nil)
        }
    }

    private func move(by step: Int) {
        guard let rows = report?.rows, !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selection } ?? 0
        select(rows[min(max(current + step, 0), rows.count - 1)].id)
    }

    /// 150 ms fade, none with "Reducir movimiento".
    private func fade(_ view: NSView, to alpha: Double, from start: Double) {
        guard let duration = theme?.observatory.fadeDuration,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else { return }
        view.alphaValue = start
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            view.animator().alphaValue = alpha
        }
    }
}
