import Foundation

/// How long highlighting waits for the disk and how long it trusts what it learned (spec F5.6, "Rutas").
public struct HighlightTiming: Sendable {
    public static let standard = HighlightTiming(budget: .milliseconds(3)) { Date() }
    /// Seconds a path's answer is reused for the same directory and word.
    public static let cacheLifetime: TimeInterval = 2

    public let budget: Duration
    /// The complete answer stops waiting for the disk after this; what is still missing stays without a span.
    public let completeLimit: Duration
    public let now: @Sendable () -> Date

    public init(budget: Duration, completeLimit: Duration = .seconds(2), now: @escaping @Sendable () -> Date) {
        self.budget = budget
        self.completeLimit = completeLimit
        self.now = now
    }
}

/// The first answer may lack the paths that took longer than the budget and the subcommands of specs not loaded
/// yet; `isComplete` says whether a complete answer would differ.
public struct HighlightAnswer: Equatable, Sendable {
    public let spans: [HighlightSpan]
    public let isComplete: Bool

    public init(spans: [HighlightSpan], isComplete: Bool) {
        self.spans = spans
        self.isComplete = isComplete
    }
}

/// HighlightLine (spec F5.6): the spans of the line being typed. The first answer never waits for JavaScript and
/// waits for the disk at most `budget`; the complete one loads the specs and waits for every path.
public actor HighlightLine {
    private struct Cached {
        let kind: PathKind?
        let date: Date
    }

    private let paths: any PathFacts
    private let completions: any CompletionProvider
    private let timing: HighlightTiming
    private var cache: [String: Cached] = [:]
    private var inFlight: [String: Task<PathKind?, Never>] = [:]
    private var specCommands: Set<String>?
    /// Commands whose spec failed to load: nothing more will come, so they no longer make an answer incomplete.
    private var unavailableSpecs: Set<String> = []

    public init(paths: any PathFacts, completions: any CompletionProvider, timing: HighlightTiming = .standard) {
        self.paths = paths
        self.completions = completions
        self.timing = timing
    }

    /// Paths remembered now; expired ones are dropped at the next lookup, so a long session does not grow it.
    public var cachedPathCount: Int { cache.count }

    public func firstAnswer(_ line: InputLine, directory: String, home: String) async -> HighlightAnswer {
        let plan = await plan(for: line.text, loading: false)
        let resolved = await kinds(
            of: plan.pathCandidates, where: Place(directory: directory, home: home), waitingFor: timing.budget)
        let missingSpecs = await commandsWithUnloadedSpec(plan.commandsWithoutSpec)
        return HighlightAnswer(
            spans: Self.merge(plan.spans, paths: resolved.spans), isComplete: resolved.isComplete && !missingSpecs)
    }

    public func completeAnswer(_ line: InputLine, directory: String, home: String) async -> [HighlightSpan] {
        let plan = await plan(for: line.text, loading: true)
        let resolved = await kinds(
            of: plan.pathCandidates, where: Place(directory: directory, home: home), waitingFor: timing.completeLimit)
        return Self.merge(plan.spans, paths: resolved.spans)
    }

    // MARK: - Specs

    /// The line's plan with the specs at hand. Each pass may reveal new commands (`xargs git …` shows `git` once
    /// `xargs`' spec is known), so it repeats while it finds specs for them, a few times at most.
    private func plan(for text: String, loading: Bool) async -> HighlightPlan {
        var specs: [String: CompletionSpec] = [:]
        var asked: Set<String> = []
        var plan = LineHighlighter.plan(for: text) { _ in nil }
        for _ in 0..<Self.specPasses {
            let names = Set(plan.commandsWithoutSpec).subtracting(asked)
            guard !names.isEmpty else { break }
            asked.formUnion(names)
            for name in names {
                let spec = loading ? await completions.spec(for: name) : await completions.loadedSpec(for: name)
                if let spec { specs[name] = spec } else if loading { unavailableSpecs.insert(name) }
            }
            plan = LineHighlighter.plan(for: text) { specs[$0] }
        }
        return plan
    }

    private static let specPasses = 3

    private func commandsWithUnloadedSpec(_ names: [String]) async -> Bool {
        guard !names.isEmpty else { return false }
        if specCommands == nil { specCommands = Set(await completions.commands) }
        return names.contains { specCommands?.contains($0) == true && !unavailableSpecs.contains($0) }
    }

    // MARK: - Paths

    private struct Place {
        let directory: String
        let home: String
    }

    private struct Resolved {
        let spans: [HighlightSpan]
        let isComplete: Bool
    }

    private struct Query {
        let candidate: PathCandidate
        let path: String
        let key: String
    }

    private enum Event {
        case answered(key: String, kind: PathKind?)
        case timedOut
    }

    /// Asks for every candidate at once and takes the answers that arrive within `limit`. A late lookup keeps
    /// running and stores its answer when it comes, for the next answer.
    private func kinds(of candidates: [PathCandidate], where place: Place, waitingFor limit: Duration) async
        -> Resolved
    {
        cache = cache.filter { isFresh($0.value) }
        let queries = candidates.compactMap { candidate in
            Self.absolute(candidate.word, in: place).map {
                Query(candidate: candidate, path: $0, key: place.directory + "\u{0}" + candidate.word)
            }
        }
        await lookUp(queries.filter { !isCached($0.key) }, waitingFor: limit)
        var spans: [HighlightSpan] = []
        var isComplete = true
        for query in queries {
            guard let cached = cache[query.key], isFresh(cached) else {
                isComplete = false
                continue
            }
            if cached.kind != nil { spans.append(HighlightSpan(range: query.candidate.range, role: .path)) }
        }
        return Resolved(spans: spans, isComplete: isComplete)
    }

    private func lookUp(_ queries: [Query], waitingFor limit: Duration) async {
        guard !queries.isEmpty else { return }
        let (events, sink) = AsyncStream.makeStream(of: Event.self)
        for query in queries {
            let task = inFlight[query.key] ?? lookUpTask(query)
            inFlight[query.key] = task
            Task { sink.yield(.answered(key: query.key, kind: await task.value)) }
        }
        let deadline = ContinuousClock.now + limit
        Task {
            try? await Task.sleep(until: deadline, clock: .continuous)
            sink.yield(.timedOut)
        }
        var pending = Set(queries.map(\.key))
        for await event in events {
            guard case .answered(let key, _) = event else { break }
            pending.remove(key)
            if pending.isEmpty { break }
        }
        sink.finish()
    }

    /// The lookup stores its own answer, even after every waiting answer gave up on it.
    private func lookUpTask(_ query: Query) -> Task<PathKind?, Never> {
        Task { [paths] in
            let kind = await paths.kind(of: query.path)
            store(kind, for: query.key)
            return kind
        }
    }

    private func store(_ kind: PathKind?, for key: String) {
        inFlight[key] = nil
        cache[key] = Cached(kind: kind, date: timing.now())
    }

    private func isCached(_ key: String) -> Bool {
        cache[key].map(isFresh) ?? false
    }

    private func isFresh(_ cached: Cached) -> Bool {
        timing.now().timeIntervalSince(cached.date) < HighlightTiming.cacheLifetime
    }

    /// `~` and `~/…` expand with the home; `~user` is left alone; a relative word goes under the directory.
    private static func absolute(_ word: String, in place: Place) -> String? {
        if word == "~" { return place.home }
        if word.hasPrefix("~/") { return place.home + word.dropFirst() }
        if word.hasPrefix("~") { return nil }
        if word.hasPrefix("/") { return word }
        return place.directory.hasSuffix("/") ? place.directory + word : place.directory + "/" + word
    }

    /// A path span goes right after the spans of its own word, so zsh underlines on top of the word's color.
    private static func merge(_ spans: [HighlightSpan], paths: [HighlightSpan]) -> [HighlightSpan] {
        (spans + paths).enumerated().sorted { lhs, rhs in
            lhs.element.range.lowerBound != rhs.element.range.lowerBound
                ? lhs.element.range.lowerBound < rhs.element.range.lowerBound : lhs.offset < rhs.offset
        }.map(\.element)
    }
}
