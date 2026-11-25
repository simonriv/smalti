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

    init(registry: HarnessRegistry) {
        search = SearchHarnessSessions(registry: registry)
        opener = OpenHarnessSession(
            registry: registry, directoryExists: { FileManager.default.fileExists(atPath: $0) }, clock: { Date() })
    }

    func refresh() {
        running?.cancel()
        let stream = search.run(state.query)
        running = Task { [weak self] in
            for await listing in stream {
                guard let self, !Task.isCancelled else { return }
                state.listing = listing
                onChange?()
            }
        }
    }

    func stop() {
        running?.cancel()
        running = nil
    }

    func setText(_ text: String) {
        guard text != state.text else { return }
        state.text = text
        refresh()
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
