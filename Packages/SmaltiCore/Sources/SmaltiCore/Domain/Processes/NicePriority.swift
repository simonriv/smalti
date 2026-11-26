/// How a nice value reads: below 0 only root can set it.
public enum PriorityLevel: Equatable, Sendable {
    case high
    case normal
    case low
    case lowest
}

/// Lowering priority without privileges means raising nice, in steps of 5 up to 20 (spec F8).
public enum NicePriority {
    public static let step: Int32 = 5
    public static let lowest: Int32 = 20

    /// The next lower priority; nil when it is already the lowest.
    public static func next(after nice: Int32) -> Int32? {
        guard nice < lowest else { return nil }
        // A process raised above normal by root first comes back to normal.
        guard nice >= 0 else { return 0 }
        return min(nice + step, lowest)
    }

    public static func level(of nice: Int32) -> PriorityLevel {
        switch nice {
        case ..<0: .high
        case 0: .normal
        case 1..<10: .low
        default: .lowest
        }
    }
}
