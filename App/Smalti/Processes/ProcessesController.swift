import AppKit
import Dispatch
import SmaltiCore

/// Primary adapter for ⌘⇧M and ⌘⇧U: the processes and ports views over the whole window. It samples only while
/// open (spec F8, C4), keeps the filter, order, tree and selection, and turns keys and commands into the domain's
/// use cases (`ObserveProcesses`, `StopProcess`, `LowerPriority`). It holds no rules: the tables, what can be
/// stopped and the stop's phases come from the domain.
@MainActor
final class ProcessesController {
    enum Mode: Equatable {
        case processes, ports
    }

    struct Dependencies {
        let observe: ObserveProcesses
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

    static let refreshInterval: Duration = .seconds(ProcessesPresenter.refreshSeconds)
    /// The second sample, which gives CPU, comes a second after opening.
    static let firstRefreshDelay: Duration = .seconds(1)
    /// A first refresh right after asking a process to quit, so it disappears as soon as it does.
    static let afterStopDelay: Duration = .milliseconds(400)

    private let window: NSWindow
    private let dependencies: Dependencies
    private let actions: Actions
    private var view: ProcessesView?
    private var theme: Theme?
    private(set) var mode = Mode.processes
    private var filter = ""
    private var processOrder = ProcessOrder.cpu
    private var portOrder = PortOrder.port
    private var isTree = false
    private var selection: String?
    private var snapshot: ProcessesSnapshot?
    private var output: ProcessesPresenter.Output?
    private var cpuHistory: [Double] = []
    private var refreshLoop: Task<Void, Never>?
    private var isRefreshing = false
    private var noticeTask: Task<Void, Never>?
    private var confirming: ProcessIdentity?
    private let grace: Duration

    var isOpen: Bool { view != nil }

    init(window: NSWindow, dependencies: Dependencies, actions: Actions, grace: Duration) {
        self.window = window
        self.dependencies = dependencies
        self.actions = actions
        self.grace = grace
    }

    // MARK: - Opening and closing

    /// ⌘⇧M / ⌘⇧U: opens on that view, switches to it, or closes when it is the one shown.
    func toggle(_ mode: Mode, theme: Theme) {
        guard isOpen else { return open(mode, theme: theme) }
        guard mode != self.mode else { return close(focusing: nil) }
        choose(mode)
    }

    /// Closes without moving the focus (another overlay or a notification takes it).
    func dismiss() {
        guard let view else { return }
        self.view = nil
        refreshLoop?.cancel()
        refreshLoop = nil
        noticeTask?.cancel()
        confirming.map(dependencies.stop.cancel)
        confirming = nil
        dependencies.observe.reset()
        snapshot = nil
        cpuHistory = []
        fadeOut(view, duration: theme?.observatory.fadeDuration)
        actions.setTilingHidden(false)
    }

    private func open(_ mode: Mode, theme: Theme) {
        guard let content = window.contentView else { return }
        self.mode = mode
        self.theme = theme
        let view = ProcessesView(theme: theme)
        view.frame = content.bounds
        view.autoresizingMask = [.width, .height]
        view.onKey = { [weak self] key in self?.handle(key) }
        view.onSelect = { [weak self] id in self?.select(id) }
        view.onChooseMode = { [weak self] mode in self?.choose(mode) }
        self.view = view
        content.addSubview(view)
        actions.setTilingHidden(true)
        fadeIn(view, duration: theme.observatory.fadeDuration)
        window.makeFirstResponder(view)
        startRefreshing()
    }

    private func close(focusing pane: PaneID?) {
        guard isOpen else { return }
        dismiss()
        actions.didClose(pane)
    }

    private func choose(_ mode: Mode) {
        guard mode != self.mode else { return }
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
        switch outcome {
        case .confirming:
            confirming = row.identity
            showConfirmation(for: row)
        case .requested:
            notify(outcome, about: row)
            refresh(after: Self.afterStopDelay)
            refresh(after: grace + .milliseconds(200))
        default: notify(outcome, about: row)
        }
        render()
    }

    private func confirmForce() async {
        guard let identity = confirming else { return }
        let row = output?.processes.values.first { $0.identity == identity }
        let outcome = await dependencies.stop.confirm(identity)
        confirming = nil
        view?.showConfirmation(nil)
        if let row { notify(outcome, about: row) }
        refresh(after: Self.afterStopDelay)
        render()
    }

    private func cancelForce() {
        guard let identity = confirming else { return }
        dependencies.stop.cancel(identity)
        confirming = nil
        view?.showConfirmation(nil)
        render()
    }

    private func lowerSelected() async {
        guard mode == .processes, let row = selectedProcess else { return }
        let outcome = await dependencies.lower.lower(row)
        let texts = ProcessTexts.current
        let subject = NoticeSubject(name: row.name, closeKey: chord(.paneClose))
        let isFailure: Bool
        if case .failed(let error) = outcome { isFailure = error != .gone } else { isFailure = false }
        show(notice: ProcessFormat.notice(outcome, for: subject, texts: texts), isFailure: isFailure)
        refresh(after: Self.afterStopDelay)
    }

    private var selectedProcess: ProcessRow? {
        selection.flatMap { output?.processes[$0] }
    }

    private func showConfirmation(for row: ProcessRow) {
        let texts = ProcessTexts.current
        let seconds = String(grace.components.seconds)
        view?.showConfirmation(
            ForceConfirmation.Content(
                title: texts.confirmTitle(["name": row.name, "pid": String(row.pid)]),
                body: texts.confirmBody(["seconds": seconds]),
                command: [row.command, ProcessFormat.directory(row.record.workingDirectory, home: dependencies.home)]
                    .joined(separator: " · ")))
    }

    private func notify(_ outcome: StopOutcome, about row: ProcessRow) {
        let subject = NoticeSubject(name: row.name, closeKey: chord(.paneClose))
        guard let text = ProcessFormat.notice(outcome, for: subject, texts: .current) else { return }
        show(notice: text, isFailure: ProcessFormat.isFailure(outcome))
    }

    private func show(notice text: String, isFailure: Bool) {
        view?.showNotice(text, isFailure: isFailure)
        noticeTask?.cancel()
        let seconds = theme?.processes.noticeSeconds ?? 4
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
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

    private func startRefreshing() {
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            await self?.refresh()
            try? await Task.sleep(for: Self.firstRefreshDelay)
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    private func refresh(after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            await self?.refresh()
        }
    }

    /// Never two at once; one asked for during another is dropped (the loop brings the next one).
    private func refresh() async {
        guard isOpen, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let snapshot = await dependencies.observe.refresh(foregroundGroups: actions.foregroundGroups())
        guard isOpen else { return }
        self.snapshot = snapshot
        dependencies.stop.tick(alive: snapshot.alive, now: Self.now())
        if let identity = confirming, !snapshot.alive.contains(identity) {
            confirming = nil
            view?.showConfirmation(nil)
        }
        if let cpu = snapshot.totals.cpu {
            cpuHistory.append(cpu)
            cpuHistory = Array(cpuHistory.suffix(theme?.processes.cpuHistoryLength ?? 60))
        }
        render()
    }

    private func render() {
        guard let view, let snapshot, let theme else { return }
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

    // MARK: - Motion

    /// The overlays' 150 ms fade, none with "Reducir movimiento".
    private func fadeIn(_ view: NSView, duration: Double) {
        guard !Motion.isReduced else { return }
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            view.animator().alphaValue = 1
        }
    }

    private func fadeOut(_ view: NSView, duration: Double?) {
        guard let duration, !Motion.isReduced else {
            view.removeFromSuperview()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            view.animator().alphaValue = 0
        } completionHandler: {
            view.removeFromSuperview()
        }
    }
}
