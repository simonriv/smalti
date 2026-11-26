import SmaltiCore
import Synchronization

/// `WelcomeRecord` in memory, for use cases and the shared contract.
public final class InMemoryWelcomeRecord: WelcomeRecord {
    private let done: Mutex<Bool>

    public init(isDone: Bool = false) {
        done = Mutex(isDone)
    }

    public var isDone: Bool { done.withLock { $0 } }

    public func markDone() throws(WelcomeRecordError) {
        done.withLock { $0 = true }
    }
}
