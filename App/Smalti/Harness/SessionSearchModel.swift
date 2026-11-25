import Foundation
import SmaltiCore

/// The session search's behaviour shared by the ⌘⇧O card and the restore screen's column: it keeps the state,
/// re-reads the harnesses when the query changes (slow ones arrive later) and turns the selection into an open plan.
@MainActor
final class SessionSearchModel {
    private(set) var state = SessionSearchState()
    var onChange: (() -> Void)?

    private let search: SearchHarnessSessions
    private let opener: OpenHarnessSession
    private var running: Task<Void, Never>?
    /// The query's listing is not complete yet (the pause runs, or a harness has not answered): Enter waits for it.
    private var isSettling = false
    private var whenSettledAction: (() -> Void)?
    /// Typing waits this long before reading the stores again, so a word is one search, not one per letter.
    static let typingPause: Duration = .milliseconds(100)

    init(registry: HarnessRegistry, connectsEditor: @escaping () -> Bool) {
        search = SearchHarnessSessions(registry: registry)
        opener = OpenHarnessSession(
            registry: registry, directoryExists: { FileManager.default.fileExists(atPath: $0) }, clock: { Date() },
            connectsEditor: connectsEditor)
    }

    /// A new card starts empty: no text and the "Todas" chip.
    func reset() {
        stop()
        state = SessionSearchState()
    }

    func refresh(after pause: Duration = .zero) {
        running?.cancel()
        isSettling = true
        let query = state.query
        running = Task { [weak self, search] in
            if pause > .zero {
                try? await Task.sleep(for: pause)
                guard !Task.isCancelled else { return }
            }
            for await listing in search.run(query) {
                guard let self, !Task.isCancelled else { return }
                state.listing = listing
                onChange?()
            }
            // Every harness answered (or ran out of its 500 ms): the listing is the typed text's, whole.
            guard let self, !Task.isCancelled else { return }
            settle()
        }
    }

    /// Runs `action` once the listing matches the query: now, or when every harness has answered.
    func whenSettled(_ action: @escaping () -> Void) {
        guard isSettling else { return action() }
        whenSettledAction = action
    }

    private func settle() {
        guard isSettling else { return }
        isSettling = false
        let action = whenSettledAction
        whenSettledAction = nil
        action?()
    }

    func stop() {
        running?.cancel()
        running = nil
        isSettling = false
        whenSettledAction = nil
    }

    func setText(_ text: String) {
        guard text != state.text else { return }
        state.text = text
        refresh(after: Self.typingPause)
    }

    func selectChip(_ index: Int) {
        state.selectChip(index)
        refresh()
    }

    func moveChip(by offset: Int) {
        offset > 0 ? state.nextChip() : state.previousChip()
        refresh()
    }

    func moveSelection(by offset: Int) {
        state.moveSelection(by: offset)
        onChange?()
    }

    func select(id: String) {
        state.select(id: id)
        onChange?()
    }

    func rows() -> [SessionSearchRow] { state.rows(now: Date(), calendar: .current) }

    /// The plan for the selected session; nil without one.
    func plan(forking: Bool) -> OpenPlan? {
        state.selected.map { opener.plan($0, forking: forking) }
    }

    /// The selected session's directory, for the "folder missing" notice.
    var selectedDirectory: String? { state.selected?.directory }
}
