import AppKit
import Dispatch
import SmaltiCore

/// Primary adapter for ⌘⇧M and ⌘⇧U: the processes and ports views over the whole window. It keeps the filter, order,
/// tree and selection and turns keys and commands into the domain's use cases. It holds no rules: what is shown and
/// stoppable, the stop's phases (and which process waits for confirmation) and when to sample (only while open,
/// `ProcessesRefresher`, spec F8 C4) all come from the domain.
@MainActor
final class ProcessesController {
    enum Mode: Equatable {
        case processes, ports
    }

    struct Dependencies {
        let refresher: ProcessesRefresher
        let stop: StopProcess
        let lower: LowerPriority
        let policy: StopPolicy
        let home: String
    }

    struct Actions {
        let setTilingHidden: (Bool) -> Void
        /// After closing: show this pane (↵ on a row of a pane) or give the focus back (nil).
        let didClose: (PaneID?) -> Void
        let foregroundGroups: () -> [PaneID: Int32]
        let paneNames: () -> [PaneID: String]
        let keymap: () -> Keymap
    }

    /// A refresh right after asking a process to quit, so it disappears as soon as it does.
    static let afterStopDelay: Duration = .milliseconds(400)
    /// After the grace period, so "not responding" shows without waiting for the next 2 s refresh.
    static let afterGraceMargin: Duration = .milliseconds(200)

    private let window: NSWindow
    private let dependencies: Dependencies
    private let actions: Actions
    private let grace: Duration
    private var view: ProcessesView?
    private var theme: Theme
    private(set) var mode = Mode.processes
    private var filter = ""
    private var processOrder = ProcessOrder.cpu
    private var portOrder = PortOrder.port
    private var isTree = false
    private var selection: String?
    private var snapshot: ProcessesSnapshot?
    private var output: ProcessesPresenter.Output?
    private var cpuHistory: [Double] = []
    private var noticeTask: Task<Void, Never>?

    var isOpen: Bool { view != nil }
    private var confirming: ProcessIdentity? { dependencies.stop.confirming }

    init(window: NSWindow, dependencies: Dependencies, actions: Actions, grace: Duration) {
        self.window = window
        self.dependencies = dependencies
        self.actions = actions
        self.grace = grace
        theme = .obsidian
    }

    // MARK: - Opening and closing

    /// ⌘⇧M / ⌘⇧U: opens on that view, switches to it, or closes when it is the one shown.
    func toggle(_ mode: Mode, theme: Theme) {
        guard isOpen else { return open(mode, theme: theme) }
        guard mode != self.mode else { return close(focusing: nil) }
        choose(mode)
    }

    /// Closes without moving the focus (another overlay, closing the window or a notification takes it). Nothing
    /// stays armed: no sampling, no confirmation to force, no rows of a past refresh (review 2, important 1).
    func dismiss() {
        guard let view else { return }
        self.view = nil
        dependencies.refresher.stop()
        dependencies.stop.cancelConfirmations()
        noticeTask?.cancel()
        snapshot = nil
        output = nil
        selection = nil
        cpuHistory = []
        fadeOut(view)
        actions.setTilingHidden(false)
    }

    private func open(_ mode: Mode, theme: Theme) {
        guard let content = window.contentView else { return }
        self.mode = mode
        self.theme = theme
        let view = ProcessesView(theme: theme, keymap: actions.keymap())
        view.frame = content.bounds
        view.autoresizingMask = [.width, .height]
        view.onKey = { [weak self] key in self?.handle(key) }
        view.onSelect = { [weak self] id in self?.select(id) }
        view.onChooseMode = { [weak self] mode in self?.choose(mode) }
        self.view = view
        content.addSubview(view)
        actions.setTilingHidden(true)
        fadeIn(view)
        window.makeFirstResponder(view)
        dependencies.refresher.start(foregroundGroups: actions.foregroundGroups) { [weak self] snapshot in
            self?.show(snapshot)
        }
    }

    private func close(focusing pane: PaneID?) {
        guard isOpen else { return }
        dismiss()
        actions.didClose(pane)
    }

    /// Switching views keeps a confirmation from staying armed over rows it no longer belongs to (review 2, minor 2).
    private func choose(_ mode: Mode) {
        guard mode != self.mode, confirming == nil else { return }
        self.mode = mode
        selection = nil
        render()
    }

    // MARK: - Commands (⌘⌫, ⌘⇧↓, ⌘T, ⌘⇧S)

    func perform(_ command: CommandID, theme: Theme) {
        guard isOpen else { return open(.processes, theme: theme) }
        guard confirming == nil else { return }
        switch command {
        case .processesStop: Task { await stopSelected() }
        case .processesLowerPriority: Task { await lowerSelected() }
        case .processesTree:
            guard mode == .processes else { return }
            isTree.toggle()
            render()
        case .processesSort:
            switch mode {
            case .processes: processOrder = processOrder.next
            case .ports: portOrder = portOrder.next
            }
            render()
        default: break
        }
    }

    private func stopSelected() async {
        guard let row = selectedProcess else { return }
        let outcome = await dependencies.stop.press(row, now: Self.now())
        // Closed meanwhile (esc right after ⌘⌫): nothing may stay waiting to be forced.
        guard isOpen else { return dependencies.stop.cancelConfirmations() }
        switch outcome {
        case .confirming: showConfirmation(for: row)
        case .requested:
            notify(outcome, about: row)
            refresh(after: Self.afterStopDelay)
            refresh(after: grace + Self.afterGraceMargin)
        default: notify(outcome, about: row)
        }
        render()
    }

    private func confirmForce() async {
        guard let identity = confirming else { return }
        let row = output?.processes.values.first { $0.identity == identity }
        view?.showConfirmation(nil)
        let outcome = await dependencies.stop.confirm(identity)
        if let row { notify(outcome, about: row) }
        refresh(after: Self.afterStopDelay)
        render()
    }

    private func cancelForce() {
        guard let identity = confirming else { return }
        dependencies.stop.cancel(identity)
        view?.showConfirmation(nil)
        render()
    }

    private func lowerSelected() async {
        guard mode == .processes, let row = selectedProcess else { return }
        let outcome = await dependencies.lower.lower(row)
        guard isOpen else { return }
        show(
            notice: ProcessFormat.notice(outcome, for: subject(row), texts: .current),
            isFailure: ProcessFormat.isFailure(outcome))
        refresh(after: Self.afterStopDelay)
    }

    private var selectedProcess: ProcessRow? {
        selection.flatMap { output?.processes[$0] }
    }

    private func subject(_ row: ProcessRow) -> NoticeSubject {
        NoticeSubject(name: row.name, closeKey: chord(.paneClose))
    }

    private func showConfirmation(for row: ProcessRow) {
        let texts = ProcessTexts.current
        view?.showConfirmation(
            ForceConfirmation.Content(
                title: texts.confirmTitle(["name": row.name, "pid": String(row.pid)]),
                body: texts.confirmBody(["seconds": Self.seconds(grace)]),
                command: [
                    row.record.shortCommand,
                    ProcessFormat.directory(row.record.workingDirectory, home: dependencies.home),
                ].joined(separator: " · ")))
    }

    private func notify(_ outcome: StopOutcome, about row: ProcessRow) {
        guard let text = ProcessFormat.notice(outcome, for: subject(row), texts: .current) else { return }
        show(notice: text, isFailure: ProcessFormat.isFailure(outcome))
    }

    private func show(notice text: String, isFailure: Bool) {
        view?.showNotice(text, isFailure: isFailure)
        noticeTask?.cancel()
        let duration = Duration.seconds(theme.processes.noticeSeconds)
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.view?.showNotice(nil, isFailure: false)
        }
    }

    private func chord(_ command: CommandID) -> String {
        actions.keymap().chord(for: command)?.display ?? ""
    }

    // MARK: - Keys

    private func handle(_ key: ProcessesView.Key) {
        if confirming != nil { return handleConfirmation(key) }
        switch key {
        case .up: move(by: -1)
        case .down: move(by: 1)
        case .open:
            guard let pane = selection.flatMap({ output?.panes[$0] }) else { return }
            close(focusing: pane)
        case .close:
            guard !filter.isEmpty else { return close(focusing: nil) }
            filter = ""
            render()
        case .text(let text):
            filter += text
            render()
        case .deleteBackward:
            guard !filter.isEmpty else { return }
            filter.removeLast()
            render()
        }
    }

    private func handleConfirmation(_ key: ProcessesView.Key) {
        switch key {
        case .open: Task { await confirmForce() }
        case .close: cancelForce()
        default: break
        }
    }

    private func move(by step: Int) {
        guard let rows = output?.screen.rows, !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selection } ?? 0
        select(rows[min(max(current + step, 0), rows.count - 1)].id)
    }

    private func select(_ id: String) {
        guard confirming == nil else { return }
        selection = id
        render()
    }

    // MARK: - Refreshing

    private func refresh(after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            await self?.dependencies.refresher.refreshNow()
        }
    }

    private func show(_ snapshot: ProcessesSnapshot) {
        guard isOpen else { return }
        self.snapshot = snapshot
        dependencies.stop.tick(alive: snapshot.alive, now: Self.now())
        if confirming == nil { view?.showConfirmation(nil) }
        if let cpu = snapshot.totals.cpu {
            cpuHistory = Array((cpuHistory + [cpu]).suffix(theme.processes.cpuHistoryLength))
        }
        render()
    }

    private func render() {
        guard let view, let snapshot else { return }
        let presenter = ProcessesPresenter(
            texts: .current, tokens: theme.processes, home: dependencies.home, keymap: actions.keymap(), now: Date())
        let input = snapshot.input(
            policy: dependencies.policy, paneNames: actions.paneNames(), phases: dependencies.stop.requests.phases)
        let output = presenter.make(
            snapshot, input: input,
            state: .init(
                mode: mode, filter: filter, processOrder: processOrder, portOrder: portOrder, isTree: isTree,
                selection: selection, cpuHistory: cpuHistory))
        self.output = output
        selection = output.screen.selected
        view.show(output.screen, filter: filter)
    }

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    /// "3", or "0.5" for a shortened grace in UI tests.
    private static func seconds(_ duration: Duration) -> String {
        let parts = duration.components
        let value = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        return value == value.rounded() ? String(Int(value)) : String(value)
    }

    // MARK: - Motion

    /// The overlays' 150 ms fade, none with "Reducir movimiento".
    private func fadeIn(_ view: NSView) {
        guard !Motion.isReduced else { return }
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = theme.observatory.fadeDuration
            view.animator().alphaValue = 1
        }
    }

    private func fadeOut(_ view: NSView) {
        guard !Motion.isReduced else {
            view.removeFromSuperview()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = theme.observatory.fadeDuration
            view.animator().alphaValue = 0
        } completionHandler: {
            view.removeFromSuperview()
        }
    }
}
