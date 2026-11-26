import Foundation

/// The timeline's search over a project's sessions (spec F9, section 4): waits for typing to pause, searches each
/// harness in turn and keeps only confirmed matches; a new query or closing cancels the one running.
@MainActor
public final class SearchTranscripts {
    private let sources: TranscriptSources
    private let policy: any TranscriptTextPolicy
    private let debounce: Duration
    public private(set) var results = SearchResults()
    public private(set) var query = TimelineQuery("")
    public private(set) var isSearching = false
    public var onChange: (() -> Void)?
    private var task: Task<Void, Never>?

    public init(sources: TranscriptSources, policy: any TranscriptTextPolicy, debounce: Duration = .milliseconds(150)) {
        self.sources = sources
        self.policy = policy
        self.debounce = debounce
    }

    public func update(query text: String, root: String) {
        task?.cancel()
        query = TimelineQuery(text)
        results = SearchResults()
        isSearching = !query.isEmpty
        onChange?()
        guard isSearching else { return }
        let query = query
        task = Task { [weak self, sources, policy, debounce] in
            guard (try? await Task.sleep(for: debounce)) != nil else { return }
            // Every harness at once; each match is confirmed off the main actor (it reads whole outputs, review 1)
            // and the results keep the newest session first.
            await withTaskGroup(of: Void.self) { group in
                for project in sources.projects {
                    group.addTask {
                        var hits = project.search(query, under: root).makeAsyncIterator()
                        while let hit = try? await hits.next(), !Task.isCancelled {
                            guard let match = SearchResults.confirm(hit, query: query, policy: policy) else { continue }
                            guard await self?.add(match) == true else { return }
                        }
                    }
                }
            }
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// Adds a match; false once the search is cancelled or capped.
    private func add(_ match: SearchMatch) -> Bool {
        guard isSearching, !results.isCapped else { return false }
        results = results.adding(match)
        onChange?()
        return !results.isCapped
    }

    private func finish() {
        isSearching = false
        onChange?()
    }

    public func cancel() {
        task?.cancel()
        isSearching = false
        onChange?()
    }
}
