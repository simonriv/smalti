/// How a split places its two children.
public enum SplitAxis: String, Codable, Sendable {
    /// `first` on the left, `second` on the right.
    case sideBySide
    /// `first` on top, `second` below.
    case stacked
}
