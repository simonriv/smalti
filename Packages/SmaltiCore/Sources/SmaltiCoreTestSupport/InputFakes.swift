import Foundation
import SmaltiCore

public actor InMemoryCommandHistory: CommandHistory {
    public private(set) var entries: [HistoryEntry]
    public private(set) var loads = 0
    private var loadFailure: HistoryError?
    private var isHoldingLoads = false
    private var heldLoad: CheckedContinuation<Void, Never>?
    private var loadingWaiters: [CheckedContinuation<Void, Never>] = []

    public init(entries: [HistoryEntry] = []) {
        self.entries = entries
    }

    public func failLoading(with error: HistoryError) {
        loadFailure = error
    }

    /// Makes the next `load` wait for `releaseLoads()`, to test what happens while the history is loading.
    public func holdLoads() {
        isHoldingLoads = true
    }

    public func waitUntilLoading() async {
        if heldLoad != nil { return }
        await withCheckedContinuation { loadingWaiters.append($0) }
    }

    public func releaseLoads() {
        isHoldingLoads = false
        heldLoad?.resume()
        heldLoad = nil
    }

    public func load() async throws(HistoryError) -> [HistoryEntry] {
        loads += 1
        let snapshot = entries
        if isHoldingLoads {
            await withCheckedContinuation { continuation in
                heldLoad = continuation
                loadingWaiters.forEach { $0.resume() }
                loadingWaiters = []
            }
        }
        if let loadFailure { throw loadFailure }
        return snapshot
    }

    public func append(_ entry: HistoryEntry) async throws(HistoryError) {
        entries.append(entry)
    }
}

public struct FakeProjectContext: ProjectContext {
    private let snapshots: [String: ProjectSnapshot]

    public init(snapshots: [String: ProjectSnapshot] = [:]) {
        self.snapshots = snapshots
    }

    public func snapshot(of directory: String) async -> ProjectSnapshot { snapshots[directory] ?? .empty }
}

public struct PathRequest: Equatable, Sendable {
    public let prefix: String
    public let directory: String
    public let foldersOnly: Bool

    public init(prefix: String, directory: String, foldersOnly: Bool) {
        self.prefix = prefix
        self.directory = directory
        self.foldersOnly = foldersOnly
    }
}

public actor FakeCompletionProvider: CompletionProvider {
    private let specs: [String: CompletionSpec]
    private let generated: [GeneratorID: [Suggestion]]
    private let failing: Set<GeneratorID>
    private let pathEntries: [Suggestion]
    public private(set) var pathRequests: [PathRequest] = []
    public private(set) var generateRequests: [(generator: GeneratorID, tokens: [String])] = []

    public init(
        specs: [CompletionSpec] = [], generated: [GeneratorID: [Suggestion]] = [:], failing: Set<GeneratorID> = [],
        paths: [Suggestion] = []
    ) {
        self.specs = Dictionary(specs.flatMap { spec in spec.name.map { ($0, spec) } }) { first, _ in first }
        self.generated = generated
        self.failing = failing
        self.pathEntries = paths
    }

    public var commands: [String] { Array(specs.keys) }

    public func spec(for command: String) async -> CompletionSpec? { specs[command] }

    public func generate(_ generator: GeneratorID, tokens: [String], in directory: String) async throws(CompletionError)
        -> [Suggestion]
    {
        generateRequests.append((generator, tokens))
        if failing.contains(generator) { throw CompletionError(command: generator.spec, cause: "fake failure") }
        return generated[generator] ?? []
    }

    public func paths(matching prefix: String, in directory: String, foldersOnly: Bool) async -> [Suggestion] {
        pathRequests.append(PathRequest(prefix: prefix, directory: directory, foldersOnly: foldersOnly))
        return pathEntries
    }
}
