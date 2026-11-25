import Foundation

/// The session search (spec F6): every harness is asked at once; what answers within `timeout` makes the first
/// listing, and each harness that answers later sends an updated one, so a slow store never holds the others back.
@MainActor
public final class SearchHarnessSessions {
    public static let perAdapterTimeout: Duration = .milliseconds(500)

    private let registry: HarnessRegistry
    private let timeout: Duration

    public init(registry: HarnessRegistry, timeout: Duration = perAdapterTimeout) {
        self.registry = registry
        self.timeout = timeout
    }

    public func run(_ query: SessionQuery) -> AsyncStream<SessionListing> {
        let adapters = registry.all
        let timeout = timeout
        return AsyncStream { continuation in
            let task = Task {
                await Self.collect(adapters, query: query, timeout: timeout) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private enum Arrival: Sendable {
        case answered(Result<[HarnessSession], HarnessError>)
        case deadline
    }

    private static func collect(
        _ adapters: [any HarnessAdapter], query: SessionQuery, timeout: Duration,
        yield: @escaping (SessionListing) -> Void
    ) async {
        await withTaskGroup(of: Arrival.self) { group in
            for adapter in adapters {
                group.addTask {
                    do throws(HarnessError) {
                        return .answered(.success(try await adapter.listSessions(query)))
                    } catch {
                        return .answered(.failure(error))
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .deadline
            }
            var results: [Result<[HarnessSession], HarnessError>] = []
            var pastDeadline = false
            for await arrival in group {
                switch arrival {
                case .deadline:
                    pastDeadline = true
                    if results.count < adapters.count { yield(SessionCatalog.merge(results, query: query)) }
                case .answered(let result):
                    results.append(result)
                    if pastDeadline || results.count == adapters.count {
                        yield(SessionCatalog.merge(results, query: query))
                    }
                    if results.count == adapters.count { group.cancelAll() }
                }
            }
        }
    }
}
