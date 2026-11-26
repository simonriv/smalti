/// F7.7: how long ago something happened, in the words of each language. The numbers are Smalti's own.
public struct TimeTexts: Sendable {
    /// `ElapsedPhrase`: under a minute.
    public let now: String
    public let minutesAgo: TextTemplate
    public let hoursAgo: TextTemplate
    public let daysAgo: TextTemplate

    public static let spanish = TimeTexts(
        now: "ahora", minutesAgo: "hace {n} min", hoursAgo: "hace {n} h", daysAgo: "hace {n} d")

    public static let english = TimeTexts(
        now: "now", minutesAgo: "{n} min ago", hoursAgo: "{n} h ago", daysAgo: "{n} d ago")
}
