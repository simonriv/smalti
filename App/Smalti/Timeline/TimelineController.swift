import AppKit
import SmaltiCore

/// Primary adapter for ⇧⌘T (spec F9): the timeline beside the panes. It keeps what is expanded and chosen and turns
/// keys into the domain's use cases; which session to show, how turns fold, what copying reads and what the search
/// confirms are the domain's. Nothing reads or watches the disk while it is closed (`ShowTimeline.close`).
@MainActor
final class TimelineController {
    /// What the focused pane means for the timeline, gathered by the window.
    struct Target: Equatable {
        let resolution: TimelineTarget.Resolution
        let root: String
        let directory: String
        let paneName: String
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
        let didClose: () -> Void
        /// The panes' area, in the content view's coordinates: the timeline sits on its right.
        let area: () -> NSRect
    }

    private let window: NSWindow
    private let dependencies: Dependencies
    private let actions: Actions
    private var view: TimelineView?
    private var theme = Theme.obsidian
    private var mode = TimelineScreen.Mode.session
    private var target: Target?
    /// A session opened from the recent list or a search result: the pane's own comes back when the focus moves.
    private var isPinned = false
    private var expanded: Set<TimelineItemID> = []
    private var selection = TimelineSelection()
    private var rows: [TimelineRow] = []
    private var listIndex: Int?
    private var noticeTask: Task<Void, Never>?
    private var pendingJump: (id: TimelineItemID, expand: Bool)?

    init(window: NSWindow, dependencies: Dependencies, actions: Actions) {
        self.window = window
        self.dependencies = dependencies
        self.actions = actions
        dependencies.show.onChange = { [weak self] in self?.sessionChanged() }
        dependencies.search.onChange = { [weak self] in self?.render() }
    }

    var isOpen: Bool { view != nil }
    private var presenter: TimelinePresenter { TimelinePresenter(texts: .current, policy: dependencies.policy) }

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
        guard let content = window.contentView else { return }
        self.theme = theme
        let view = TimelineView(theme: theme)
        let tokens = theme.timeline
        let area = actions.area()
        view.frame = NSRect(
            x: area.maxX - tokens.width - tokens.margin, y: area.minY + tokens.margin, width: tokens.width,
            height: area.height - 2 * tokens.margin)
        view.autoresizingMask = [.minXMargin, .height, .maxYMargin]
        view.onKey = { [weak self] key in self?.handle(key) }
        view.onCopy = { [weak self] in self?.copySelected(.content) }
        view.onQuery = { [weak self] text in self?.queryChanged(text) }
        view.onChoose = { [weak self] index in self?.choose(index: index) }
        self.view = view
        content.addSubview(view)
        TimelineMotion.fadeIn(view, theme: theme)
        window.makeFirstResponder(view)
        mode = .session
        follow(force: true)
    }

    /// Closes without moving the focus (another overlay or closing the window takes it).
    func dismiss() {
        guard let view else { return }
        self.view = nil
        noticeTask?.cancel()
        dependencies.search.cancel()
        dependencies.show.close()
        target = nil
        isPinned = false
        expanded = []
        selection = TimelineSelection()
        rows = []
        TimelineMotion.fadeOut(view, theme: theme)
    }

    private func close() {
        dismiss()
        actions.didClose()
    }

    // MARK: - Following the focused pane

    /// The window changed (focus, agent, binding): the timeline shows the focused pane's session.
    func follow(force: Bool = false) {
        guard isOpen, let next = actions.target() else { return }
        if !force, isPinned, next.paneName == target?.paneName { return }
        guard force || next != target else { return }
        target = next
        isPinned = false
        expanded = []
        selection = TimelineSelection()
        Task { await dependencies.show.show(next.resolution, root: next.root) }
        render()
    }

    private func sessionChanged() {
        if let jump = pendingJump, case .session = dependencies.show.state {
            pendingJump = nil
            selection = TimelineSelection(selected: jump.id)
            if jump.expand { expanded.insert(jump.id) }
        }
        render()
    }

    // MARK: - Keys

    private func handle(_ key: TimelineView.Key) {
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
        if mode == .session { dependencies.search.cancel() }
        // The search field joins the view when it is painted: focus it after.
        render()
        if mode == .session { window.makeFirstResponder(view) } else { view?.focusSearch() }
    }

    private func choose(index: Int) {
        listIndex = index
        if mode == .session, case .session = dependencies.show.state, rows.indices.contains(index) {
            selection = TimelineSelection(selected: rows[index].id)
        }
        render()
    }

    // MARK: - Search

    private func queryChanged(_ text: String) {
        listIndex = nil
        dependencies.search.update(query: text, root: target?.root ?? NSHomeDirectory())
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
        pendingJump = (id, TimelineJump.isOutput(hit.entry))
        mode = .session
        window.makeFirstResponder(view)
        openSession(hit.session)
    }

    private func openSession(_ session: HarnessSession) {
        isPinned = true
        expanded = []
        selection = TimelineSelection()
        listIndex = nil
        Task { await dependencies.show.open(session) }
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
            guard let index = listIndex, hits.indices.contains(index),
                let location = TimelineJump.location(of: hits[index].entry)
            else { return nil }
            return try await dependencies.copy.copy(at: location, harness: hits[index].session.harness)
        }
        guard case .session(let session) = dependencies.show.state, let id = selection.selected else { return nil }
        return try await dependencies.copy.copy(id, in: session.timeline, harness: session.ref.harness, part: part)
    }

    private func notice(_ text: String, isFailure: Bool) {
        noticeTask?.cancel()
        view?.showNotice(text, isFailure: isFailure)
        let seconds = theme.timeline.noticeSeconds
        noticeTask = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(seconds))) != nil else { return }
            self?.view?.showNotice(nil, isFailure: false)
        }
    }

    // MARK: - Rendering

    private func render() {
        guard let view else { return }
        view.show(screen())
    }

    private func screen() -> TimelineScreen {
        if mode == .search { return searchScreen() }
        let texts = TimelineTexts.current
        switch dependencies.show.state {
        case .closed, .loading:
            return TimelineScreen(
                mode: .session, body: .loading(texts.loading), selected: nil, keys: TimelinePresenter.sessionKeys())
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

    private func sessionScreen(_ session: ShowTimeline.TimelineSession) -> TimelineScreen {
        let previous = rows
        rows = presenter.rows(session, expanded: expanded)
        selection = selection.updated(for: rows, previous: previous)
        let stopped = StatusDotStyle.hollow(theme.agent.stopped, width: theme.agent.stoppedRingWidth)
        let live = actions.livePanes()[session.ref.sessionID]
        let closed = TimelineTexts.current.closed(["when": session.timeline.startedAt.map(TimelinePresenter.day) ?? ""])
        let paneName = isPinned ? live ?? closed : target?.paneName ?? ""
        let info = presenter.info(
            session, paneName: paneName, agentDot: isPinned ? stopped : target?.agentDot ?? stopped)
        return TimelineScreen(
            mode: .session,
            body: .session(
                info: info, banner: presenter.banner(session, directory: target?.directory ?? ""), rows: rows),
            selected: rows.firstIndex { $0.id == selection.selected }, keys: TimelinePresenter.sessionKeys())
    }

    private func emptyScreen(title: String, body: String, recent: [HarnessSession]) -> TimelineScreen {
        let texts = TimelineTexts.current
        let project = target.map { URL(filePath: $0.root).lastPathComponent } ?? ""
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
        let root = target?.root ?? ""
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

/// The panel's 150 ms fade and 8 pt slide; none with "Reducir movimiento".
@MainActor
enum TimelineMotion {
    static func fadeIn(_ view: NSView, theme: Theme) {
        guard !Motion.isReduced else { return }
        let target = view.frame.origin
        view.alphaValue = 0
        view.setFrameOrigin(NSPoint(x: target.x + theme.timeline.fadeOffset, y: target.y))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = theme.observatory.fadeDuration
            view.animator().alphaValue = 1
            view.animator().setFrameOrigin(target)
        }
    }

    static func fadeOut(_ view: NSView, theme: Theme) {
        guard !Motion.isReduced else { return view.removeFromSuperview() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = theme.observatory.fadeDuration
            view.animator().alphaValue = 0
        } completionHandler: {
            view.removeFromSuperview()
        }
    }
}
