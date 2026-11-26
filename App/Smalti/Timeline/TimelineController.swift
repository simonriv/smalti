import AppKit
import SmaltiCore

/// Primary adapter for ⇧⌘T (spec F9): the timeline beside the panes. It keeps what is expanded and chosen and turns
/// keys into the domain's use cases; which session to show (`TimelineTarget`, `TimelineFocus`), how turns fold, what
/// copying reads and what the search confirms are the domain's. Nothing reads or watches the disk while it is closed.
@MainActor
final class TimelineController {
    /// What the focused pane means for the timeline, gathered by the window.
    struct Target: Equatable {
        let focus: TimelineFocus
        let directory: String
        let agentDot: StatusDotStyle
    }

    struct Dependencies {
        let show: ShowTimeline
        let copy: CopyTimelineItem
        let search: SearchTranscripts
        let policy: any TranscriptTextPolicy
    }

    struct Actions {
        let target: () -> Target?
        /// Sessions open in some pane: session id → "<workspace> · <n>".
        let livePanes: () -> [String: String]
        /// The state dot of the pane where a session lives, if it lives in one.
        let liveDot: (String) -> StatusDotStyle?
        let didClose: () -> Void
        /// The panes' area: the timeline sits on its right, pinned to it by constraints.
        let area: () -> NSView?
        /// The chord that opens the timeline, as the keymap has it (final review, M5).
        let toggleKeys: () -> String
    }

    private let window: NSWindow
    private let dependencies: Dependencies
    private let actions: Actions
    private var view: TimelineView?
    private var trailing: NSLayoutConstraint?
    private var theme = Theme.obsidian
    private var mode = TimelineScreen.Mode.session
    private var target: Target?
    /// A session opened from the recent list or a search result: the pane's own comes back when the focus moves.
    private var isPinned = false
    private var expanded: Set<TimelineItemID> = []
    private var selection = TimelineSelection()
    private var rows: [TimelineRow] = []
    /// Rows are rebuilt only when the session or what is expanded changed (review 2, I5).
    private var sessionVersion = 0
    private var rowsBuilt: (version: Int, expanded: Set<TimelineItemID>)?
    private var listIndex: Int?
    private var noticeTask: Task<Void, Never>?
    private var loadingTask: Task<Void, Never>?
    private var searchPaint: Task<Void, Never>?
    private var lastScreen: TimelineScreen?
    private var pendingJump: (id: TimelineItemID, expand: Bool)?
    /// The timeline has the keyboard (opened, clicked or searched); a click on a pane gives it back to the panes.
    private(set) var hasKeyboard = false

    init(window: NSWindow, dependencies: Dependencies, actions: Actions) {
        self.window = window
        self.dependencies = dependencies
        self.actions = actions
        dependencies.show.onChange = { [weak self] in self?.sessionChanged() }
        dependencies.search.onChange = { [weak self] in self?.searchChanged() }
    }

    var isOpen: Bool { view != nil }
    private var presenter: TimelinePresenter { TimelinePresenter(texts: .current, policy: dependencies.policy) }
    private var tokens: TimelineTokens { theme.timeline }

    // MARK: - Opening and closing

    func toggle(theme: Theme) {
        guard isOpen else { return open(theme: theme) }
        if mode == .search { return choose(.session) }
        close()
    }

    /// ⌘F with the timeline open, or "Buscar en las sesiones del proyecto" from ⌘K.
    func openSearch(theme: Theme) {
        if !isOpen { open(theme: theme) }
        choose(.search)
    }

    private func open(theme: Theme) {
        guard let content = window.contentView, let area = actions.area() else { return }
        self.theme = theme
        let view = TimelineView(theme: theme, toggleKeys: actions.toggleKeys())
        view.onKey = { [weak self] key in self?.handle(key) }
        view.onCopy = { [weak self] in self?.copySelected(.content) }
        view.onQuery = { [weak self] text in self?.queryChanged(text) }
        view.onChoose = { [weak self] index in self?.choose(index: index) }
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        let trailing = view.trailingAnchor.constraint(equalTo: area.trailingAnchor, constant: -tokens.margin)
        NSLayoutConstraint.activate([
            trailing, view.widthAnchor.constraint(equalToConstant: tokens.width),
            view.topAnchor.constraint(equalTo: area.topAnchor, constant: tokens.margin),
            view.bottomAnchor.constraint(equalTo: area.bottomAnchor, constant: -tokens.margin),
        ])
        self.view = view
        self.trailing = trailing
        TimelineMotion.fadeIn(view, trailing: trailing, theme: theme)
        mode = .session
        takeKeyboard()
        follow(force: true)
    }

    /// Closes without moving the focus (another overlay or closing the window takes it). Nothing stays: no read,
    /// watcher, search, jump or rows (spec C6).
    func dismiss() {
        guard let view else { return }
        self.view = nil
        noticeTask?.cancel()
        loadingTask?.cancel()
        searchPaint?.cancel()
        dependencies.search.clear()
        dependencies.show.close()
        target = nil
        isPinned = false
        hasKeyboard = false
        pendingJump = nil
        listIndex = nil
        lastScreen = nil
        rowsBuilt = nil
        expanded = []
        selection = TimelineSelection()
        rows = []
        if let trailing { TimelineMotion.fadeOut(view, trailing: trailing, theme: theme) }
        trailing = nil
    }

    private func close() {
        dismiss()
        actions.didClose()
    }

    // MARK: - Keyboard

    /// Gives the keyboard to the timeline: its search field while searching, else the list.
    func takeKeyboard() {
        guard let view else { return }
        hasKeyboard = true
        // Already there: focusing the search field again would select the query's text.
        switch mode {
        case .search where !view.isSearching: view.focusSearch()
        case .session where window.firstResponder !== view: window.makeFirstResponder(view)
        default: break
        }
    }

    /// The keyboard is inside the timeline (its list or its search field) right now.
    var ownsFirstResponder: Bool {
        guard let view, let responder = window.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: view)
    }

    /// A click on a pane: the panes have the keyboard until the timeline is used again (review 2, C3).
    func releaseKeyboard() {
        hasKeyboard = false
    }

    // MARK: - Following the focused pane

    /// The window changed (focus, agent, binding): the focused pane's session is read only when it is another
    /// session, root or pane; its look (state dot, name) only repaints (review 2, C2).
    func follow(force: Bool = false) {
        guard isOpen, let next = actions.target() else { return }
        let change = force ? .read : TimelineFocus.change(from: target?.focus, to: next.focus, isPinned: isPinned)
        target = next
        guard change == .read else { return render() }
        isPinned = false
        pendingJump = nil
        expanded = []
        selection = TimelineSelection()
        // Started on the main actor: a close that comes first leaves it nothing to do (final review, M3).
        Task { [weak self] in
            guard let self, isOpen else { return }
            await dependencies.show.show(next.focus.resolution, root: next.focus.root)
        }
        render()
    }

    private func sessionChanged() {
        sessionVersion += 1
        switch dependencies.show.state {
        case .session:
            if let jump = pendingJump, case .session(let session) = dependencies.show.state {
                pendingJump = nil
                selection = TimelineSelection(selected: jump.id)
                // A turn inside a subagent shows only with every tool above it open (final review, I1).
                expanded.formUnion(session.timeline.ancestors(of: jump.id))
                if jump.expand { expanded.insert(jump.id) }
            }
        case .loading, .closed: break
        default: pendingJump = nil
        }
        render()
    }

    private func searchChanged() {
        // Up to 200 matches come one by one: paint at most every 50 ms (review 2, I5).
        guard searchPaint == nil else { return }
        searchPaint = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            self?.searchPaint = nil
            self?.render()
        }
    }

    // MARK: - Keys

    private func handle(_ key: TimelineView.Key) {
        hasKeyboard = true
        switch (mode, key) {
        case (_, .close): mode == .search ? choose(.session) : close()
        case (.search, .up), (.search, .down): moveHit(key == .up ? -1 : 1)
        case (.search, .open): jumpToHit()
        case (.session, .text(let text)):
            openSearch(theme: theme)
            view?.setQuery(text)
            queryChanged(text)
        case (.session, _): handleSession(key)
        default: break
        }
    }

    private func handleSession(_ key: TimelineView.Key) {
        guard case .session = dependencies.show.state else { return moveRecent(key) }
        switch key {
        case .up: selection = selection.moved(.up, in: rows)
        case .down: selection = selection.moved(.down, in: rows)
        case .right: expanded = selection.expanding(in: rows, expanded: expanded)
        case .left: (selection, expanded) = selection.collapsing(in: rows, expanded: expanded)
        default: return
        }
        render()
    }

    private func moveRecent(_ key: TimelineView.Key) {
        let recent = recentSessions
        guard !recent.isEmpty else { return }
        switch key {
        case .up: listIndex = max(0, (listIndex ?? 0) - 1)
        case .down: listIndex = min(recent.count - 1, (listIndex ?? -1) + 1)
        case .open:
            guard let index = listIndex, recent.indices.contains(index) else { return }
            openSession(recent[index])
            return
        default: return
        }
        render()
    }

    private var recentSessions: [HarnessSession] {
        switch dependencies.show.state {
        case .empty(let recent), .unreadable(_, let recent): recent
        default: []
        }
    }

    private func choose(_ mode: TimelineScreen.Mode) {
        self.mode = mode
        listIndex = nil
        if mode == .session { dependencies.search.clear() }
        // The search field joins the view when it is painted: focus it after.
        render()
        takeKeyboard()
    }

    /// A click on a row, a hit or a recent session: it is chosen and the timeline takes the keyboard (review 2, M4).
    private func choose(index: Int) {
        listIndex = index
        if mode == .session, case .session = dependencies.show.state, rows.indices.contains(index) {
            selection = TimelineSelection(selected: rows[index].id)
        }
        render()
        takeKeyboard()
    }

    // MARK: - Search

    private func queryChanged(_ text: String) {
        listIndex = nil
        // Without a focused pane there is no project: never the whole ~/.claude (final review, M4).
        guard let root = target?.focus.root else { return dependencies.search.clear() }
        dependencies.search.update(query: text, root: root)
    }

    private var hits: [SearchMatch] { dependencies.search.results.groups.flatMap(\.matches) }

    private func moveHit(_ step: Int) {
        let count = hits.count
        guard count > 0 else { return }
        listIndex = min(count - 1, max(0, (listIndex ?? -1) + step))
        render()
    }

    private func jumpToHit() {
        guard let index = listIndex, hits.indices.contains(index) else { return }
        let hit = hits[index]
        guard let id = TimelineJump.itemID(of: hit.entry) else { return }
        // In the session already shown only the choice moves (spec §5, review 2 I4).
        if case .session(let shown) = dependencies.show.state, shown.ref.harness == hit.session.harness,
            shown.ref.sessionID == hit.session.id
        {
            selection = TimelineSelection(selected: id)
            expanded.formUnion(shown.timeline.ancestors(of: id))
            if TimelineJump.isOutput(hit.entry) { expanded.insert(id) }
            return choose(.session)
        }
        pendingJump = (id, TimelineJump.isOutput(hit.entry))
        mode = .session
        dependencies.search.clear()
        openSession(hit.session)
        takeKeyboard()
    }

    private func openSession(_ session: HarnessSession) {
        isPinned = true
        expanded = []
        selection = TimelineSelection()
        listIndex = nil
        Task { [weak self] in
            guard let self, isOpen else { return }
            await dependencies.show.open(session)
        }
        render()
    }

    // MARK: - Copying

    func copySelected(_ part: CopyPart) {
        guard isOpen else { return }
        Task {
            do throws(TranscriptReadError) {
                let copied = try await copied(part)
                guard let copied else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copied.text, forType: .string)
                notice(
                    TimelineTexts.current.copied(["size": TimelineTexts.current.size(copied.byteCount)]),
                    isFailure: false)
            } catch {
                notice(error.message(.current), isFailure: true)
            }
        }
    }

    private func copied(_ part: CopyPart) async throws(TranscriptReadError) -> CopiedText? {
        if mode == .search {
            guard let index = listIndex, hits.indices.contains(index) else { return nil }
            let entry = hits[index].entry
            // ⇧⌘C copies a call or nothing (amendment 4).
            if part == .call, case .toolCall = entry.kind {} else if part == .call { return nil }
            guard let location = TimelineJump.location(of: entry) else { return nil }
            return try await dependencies.copy.copy(at: location, harness: hits[index].session.harness)
        }
        guard case .session(let session) = dependencies.show.state, let id = selection.selected else { return nil }
        return try await dependencies.copy.copy(id, in: session.timeline, harness: session.ref.harness, part: part)
    }

    private func notice(_ text: String, isFailure: Bool) {
        noticeTask?.cancel()
        view?.showNotice(text, isFailure: isFailure)
        let seconds = tokens.noticeSeconds
        noticeTask = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(seconds))) != nil else { return }
            self?.view?.showNotice(nil, isFailure: false)
        }
    }

    // MARK: - Rendering

    private func render() {
        guard let view else { return }
        let screen = screen()
        guard screen != lastScreen else { return }
        lastScreen = screen
        view.show(screen)
    }

    private func screen() -> TimelineScreen {
        if mode == .search { return searchScreen() }
        let texts = TimelineTexts.current
        switch dependencies.show.state {
        case .closed, .loading:
            return loadingScreen(texts)
        case .failed(let error):
            return TimelineScreen(
                mode: .session, body: .failed(error.message(texts)), selected: nil, keys: TimelinePresenter.emptyKeys())
        case .empty(let recent):
            return emptyScreen(title: texts.noAgentTitle, body: texts.noAgentBody, recent: recent)
        case .unreadable(let harness, let recent):
            return emptyScreen(
                title: texts.unreadableTitle(["harness": harness.displayName]), body: texts.unreadableBody,
                recent: recent)
        case .session(let session):
            return sessionScreen(session)
        }
    }

    /// "Leyendo…" only after 150 ms: a quick switch keeps what was shown, without a flash (review 2, M6).
    private func loadingScreen(_ texts: TimelineTexts) -> TimelineScreen {
        let loading = TimelineScreen(
            mode: .session, body: .loading(texts.loading), selected: nil, keys: TimelinePresenter.sessionKeys())
        // Leaving the search for another session shows "Reading…" at once (final review, M2).
        guard let shown = lastScreen, shown.mode == .session else { return loading }
        guard loadingTask == nil else { return shown }
        loadingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(self?.tokens.loadingDelayMilliseconds ?? 0)))
            guard let self else { return }
            loadingTask = nil
            if case .loading = dependencies.show.state, mode == .session {
                lastScreen = loading
                view?.show(loading)
            }
        }
        return shown
    }

    private func sessionScreen(_ session: ShowTimeline.TimelineSession) -> TimelineScreen {
        if rowsBuilt?.version != sessionVersion || rowsBuilt?.expanded != expanded {
            let previous = rows
            rows = presenter.rows(session, expanded: expanded)
            rowsBuilt = (sessionVersion, expanded)
            selection = selection.updated(for: rows, previous: previous)
        }
        let stopped = StatusDotStyle.hollow(theme.agent.stopped, width: theme.agent.stoppedRingWidth)
        let id = session.ref.sessionID
        let closed = TimelineTexts.current.closed(["when": session.timeline.startedAt.map(TimelinePresenter.day) ?? ""])
        let paneName = isPinned ? actions.livePanes()[id] ?? closed : target?.focus.pane ?? ""
        let dot = isPinned ? actions.liveDot(id) ?? stopped : target?.agentDot ?? stopped
        let info = presenter.info(session, paneName: paneName, agentDot: dot)
        return TimelineScreen(
            mode: .session,
            body: .session(
                info: info, banner: presenter.banner(session, directory: target?.directory ?? ""), rows: rows),
            selected: rows.firstIndex { $0.id == selection.selected }, keys: TimelinePresenter.sessionKeys())
    }

    private func emptyScreen(title: String, body: String, recent: [HarnessSession]) -> TimelineScreen {
        let texts = TimelineTexts.current
        let project = target.map { URL(filePath: $0.focus.root).lastPathComponent } ?? ""
        let recentTitle = recent.isEmpty ? texts.noSessions : texts.recent(["project": project])
        return TimelineScreen(
            mode: .session,
            body: .empty(
                title: title, body: body, recentTitle: recentTitle,
                recent: presenter.recent(recent, live: Set(actions.livePanes().keys))),
            selected: listIndex, keys: TimelinePresenter.emptyKeys())
    }

    private func searchScreen() -> TimelineScreen {
        let search = dependencies.search
        let current: String? =
            if case .session(let session) = dependencies.show.state { session.ref.sessionID } else { nil }
        let items = presenter.searchItems(search.results, currentSession: current, live: actions.livePanes())
        let hitRows = items.indices.filter { if case .hit = items[$0] { true } else { false } }
        let root = target?.focus.root ?? ""
        return TimelineScreen(
            mode: .search,
            body: .search(
                query: search.query.raw,
                scope: TimelineTexts.current.projectScope(["name": URL(filePath: root).lastPathComponent]),
                root: root.replacingOccurrences(of: NSHomeDirectory(), with: "~"), summary: presenter.summary(search),
                items: items),
            selected: listIndex.flatMap { hitRows.indices.contains($0) ? hitRows[$0] : nil },
            keys: TimelinePresenter.searchKeys())
    }
}

/// Where a search hit leads in the timeline, and where its text lives.
enum TimelineJump {
    static func itemID(of entry: TranscriptEntry) -> TimelineItemID? {
        switch entry.kind {
        case .prompt(let text), .reply(let text): .at(text.location)
        case .toolCall(let call): .tool(call.id)
        case .toolResult(let result): .tool(result.id)
        case .image(let image): .at(image.location)
        case .compaction(let note): .at(note.location)
        case .subagentLink: nil
        }
    }

    static func isOutput(_ entry: TranscriptEntry) -> Bool {
        if case .toolResult = entry.kind { true } else { false }
    }

    static func location(of entry: TranscriptEntry) -> TextLocation? {
        switch entry.kind {
        case .prompt(let text), .reply(let text): text.location
        case .toolCall(let call): call.call.location
        case .toolResult(let result): result.output.location
        case .image, .compaction, .subagentLink: nil
        }
    }
}

/// The panel's 150 ms fade and 8 pt slide in and out; none with "Reducir movimiento".
@MainActor
enum TimelineMotion {
    static func fadeIn(_ view: NSView, trailing: NSLayoutConstraint, theme: Theme) {
        guard !Motion.isReduced else { return }
        let resting = trailing.constant
        view.alphaValue = 0
        trailing.constant = resting + theme.timeline.fadeOffset
        view.superview?.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = theme.observatory.fadeDuration
            context.allowsImplicitAnimation = true
            view.animator().alphaValue = 1
            trailing.animator().constant = resting
        }
    }

    static func fadeOut(_ view: NSView, trailing: NSLayoutConstraint, theme: Theme) {
        guard !Motion.isReduced else { return view.removeFromSuperview() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = theme.observatory.fadeDuration
            view.animator().alphaValue = 0
            trailing.animator().constant = trailing.constant + theme.timeline.fadeOffset
        } completionHandler: {
            MainActor.assumeIsolated { view.removeFromSuperview() }
        }
    }
}
