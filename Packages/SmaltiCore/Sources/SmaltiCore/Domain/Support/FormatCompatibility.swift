/// F7.6: how a stored format version compares with the one this build understands. A file without a version is
/// format 1. A newer one is never renamed nor overwritten: going back to an older Smalti must not lose it.
public enum FormatCompatibility: Equatable, Sendable {
    case current
    /// Read and migrated in memory; written in the current format on the next save.
    case older(Int)
    /// Read as far as possible, or not at all, and left as it is.
    case newer(Int)

    public static func of(stored: Int?, current: Int) -> FormatCompatibility {
        let version = stored ?? 1
        if version == current { return .current }
        return version < current ? .older(version) : .newer(version)
    }

    public var isNewer: Bool {
        if case .newer = self { return true }
        return false
    }
}
