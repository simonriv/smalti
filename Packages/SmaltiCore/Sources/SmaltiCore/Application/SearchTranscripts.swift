import Foundation

/// The timeline's search over a project's sessions (spec F9, section 4): waits for typing to pause, searches each
/// harness in turn and keeps only confirmed matches; a new query or closing cancels the one running.
@MainActor
public final class SearchTranscripts {
    private let sources: TranscriptSources
    private let debounce: Duration
    public private(set) var results = SearchResults()
    public private(set) var query = TimelineQuery("")
    public private(set) var isSearching = false
    public var onChange: (() -> Void)?
    private var task: Task<Void, Never>?

    public init(sources: TranscriptSources, debounce: Duration = .milliseconds(150)) {
        self.sources = sources
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
        task = Task { [weak self, sources, debounce] in
            guard (try? await Task.sleep(for: debounce)) != nil else { return }
            for project in sources.projects {
                // A harness that fails ends its own results; what it found stays and the next one is searched.
                var hits = project.search(query, under: root).makeAsyncIterator()
                while let hit = try? await hits.next() {
                    guard let self, !Task.isCancelled else { return }
                    self.results = self.results.adding(hit, query: query)
                    self.onChange?()
                    if self.results.isCapped { break }
                }
                if self?.results.isCapped ?? true { break }
            }
            guard let self, !Task.isCancelled else { return }
            self.isSearching = false
            self.onChange?()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        isSearching = false
        onChange?()
    }
}
