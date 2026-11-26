public enum PriorityOutcome: Equatable, Sendable {
    case lowered(to: Int32)
    case alreadyLowest
    case protected(ProtectionReason)
    case failed(ProcessControlError)
}

/// Lowers a process's priority one step (raises its nice by 5, up to 20); never raises it.
public struct LowerPriority: Sendable {
    private let control: any ProcessControl

    public init(control: any ProcessControl) {
        self.control = control
    }

    public func lower(_ row: ProcessRow) async -> PriorityOutcome {
        if case .protected(let reason) = row.verdict { return .protected(reason) }
        guard let next = NicePriority.next(after: row.record.nice) else { return .alreadyLowest }
        do {
            try await control.lowerPriority(row.identity, to: next)
            return .lowered(to: next)
        } catch {
            return .failed(error)
        }
    }
}
