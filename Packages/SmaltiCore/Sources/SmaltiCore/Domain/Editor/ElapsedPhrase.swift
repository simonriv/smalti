import Foundation

/// How long ago Claude edited a file, as ⌘K's subtitle says it: "ahora", "hace 2 min", "hace 3 h", "hace 4 d".
public enum ElapsedPhrase {
    public static func text(since date: Date, now: Date, texts: TimeTexts) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return texts.now
        case ..<3600: return texts.minutesAgo(["n": String(seconds / 60)])
        case ..<86_400: return texts.hoursAgo(["n": String(seconds / 3600)])
        default: return texts.daysAgo(["n": String(seconds / 86_400)])
        }
    }
}
