import SmaltiCore

/// F7.7: what every `WelcomeRecord` must do; each implementation runs it on a fresh record.
public enum WelcomeRecordContract {
    /// Problems found, empty when the record behaves: fresh is not done, marking makes it done, marking twice is fine.
    public static func problems(fresh make: () -> any WelcomeRecord) async -> [String] {
        var found: [String] = []
        let record = make()
        if await record.isDone { found.append("a fresh record is already done") }
        do {
            try await record.markDone()
            try await record.markDone()
        } catch {
            found.append("marking failed: \(error)")
        }
        if await !record.isDone { found.append("a marked record is not done") }
        return found
    }
}
