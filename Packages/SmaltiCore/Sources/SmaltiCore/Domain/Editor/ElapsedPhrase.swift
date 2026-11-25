import Foundation

/// How long ago, as the palette's subtitles say it: "ahora", "hace 2 min", "hace 3 h", "hace 2 d".
public enum ElapsedPhrase {
    public static func text(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "ahora"
        case ..<3600: return "hace \(seconds / 60) min"
        case ..<86_400: return "hace \(seconds / 3600) h"
        default: return "hace \(seconds / 86_400) d"
        }
    }
}
