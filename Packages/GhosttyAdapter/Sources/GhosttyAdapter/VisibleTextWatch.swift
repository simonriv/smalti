import Foundation

/// Tells the focused terminal when its visible text changed since the last sample, so VoiceOver can be told about
/// new output at most once per `interval`.
struct VisibleTextWatch {
    static let interval: TimeInterval = 0.5

    private var last: String?

    /// True when `text` differs from the previous sample; the first sample only remembers it.
    mutating func hasChanged(_ text: String?) -> Bool {
        defer { last = text }
        guard let last else { return false }
        return text != last
    }

    /// The terminal lost the keyboard: the next sample starts over.
    mutating func forget() {
        last = nil
    }
}
