import Foundation
import SmaltiCore

@MainActor
public final class FakeTelemetrySource: TelemetrySource {
    private let stream = AsyncStream<AgentEvent>.makeStream()

    public init() {}

    public func events() -> AsyncStream<AgentEvent> { stream.stream }

    public func send(_ event: AgentEvent) {
        stream.continuation.yield(event)
    }
}

@MainActor
public final class RecordingNotifier: Notifier {
    public private(set) var delivered: [AttentionNotice] = []

    public init() {}

    public func notify(_ notice: AttentionNotice) {
        delivered.append(notice)
    }
}

@MainActor
public final class FakeHarnessIntegration: HarnessIntegration {
    public var failure: IntegrationError?
    /// The harness is not installed: its state cannot be known.
    public var isMissing = false
    private var installed = false

    public init() {}

    public func install() async throws(IntegrationError) {
        if let failure { throw failure }
        installed = true
    }

    public func uninstall() async throws(IntegrationError) {
        if let failure { throw failure }
        installed = false
    }

    public var installState: IntegrationState {
        if isMissing { return .unknown }
        return installed ? .installed : .notInstalled
    }
}

/// F7.5: guarded tool calls sent by hand.
@MainActor
public final class FakeGuardRequests: GuardRequests {
    private let stream = AsyncStream<GuardRequest>.makeStream()

    public init() {}

    public func requests() -> AsyncStream<GuardRequest> { stream.stream }

    private let cancelled = AsyncStream<UUID>.makeStream()

    public func cancellations() -> AsyncStream<UUID> { cancelled.stream }

    public func send(_ request: GuardRequest) {
        stream.continuation.yield(request)
    }
}

/// F7.5: a project's deny rules, kept in memory.
public final class InMemoryProjectPermissions: ProjectPermissions, @unchecked Sendable {
    // Only tests touch it, from one task at a time.
    public var rules: [String: [String]]
    public var failure: ProjectPermissionsError?
    public private(set) var writes = 0

    public init(rules: [String: [String]] = [:]) {
        self.rules = rules
    }

    public func deniedRules(in project: String) throws(ProjectPermissionsError) -> [String] {
        if let failure { throw failure }
        return rules[project] ?? []
    }

    public func setDeniedRules(_ rules: [String], in project: String) throws(ProjectPermissionsError) {
        if let failure { throw failure }
        writes += 1
        self.rules[project] = rules
    }
}
