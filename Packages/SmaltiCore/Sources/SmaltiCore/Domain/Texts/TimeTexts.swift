/// F7.7: how long ago something happened, in the words of each language. The numbers are Smalti's own.
public struct TimeTexts: Sendable, Equatable {
    /// `ElapsedPhrase`: under a minute.
    public let now: String
    public let minutesAgo: TextTemplate
    public let hoursAgo: TextTemplate
    public let daysAgo: TextTemplate
    /// The observatory's `ObservatoryFormat.ago`: "hace 22 min", "hace 3h", "hace 2 días".
    public let agoMinutes: TextTemplate
    public let agoHours: TextTemplate
    public let agoDays: PluralText
    /// `ObservatoryFormat.agoCompact`, for the sessions table's narrow column.
    public let compactMinutes: TextTemplate
    public let compactHours: TextTemplate
    public let compactDays: TextTemplate

    public static let spanish = TimeTexts(
        now: "ahora", minutesAgo: "hace {n} min", hoursAgo: "hace {n} h", daysAgo: "hace {n} d",
        agoMinutes: "hace {n} min", agoHours: "hace {n}h",
        agoDays: PluralText(one: "hace {count} día", other: "hace {count} días"), compactMinutes: "hace {n}m",
        compactHours: "hace {n}h", compactDays: "hace {n}d")

    public static let english = TimeTexts(
        now: "now", minutesAgo: "{n} min ago", hoursAgo: "{n} h ago", daysAgo: "{n} d ago",
        agoMinutes: "{n} min ago", agoHours: "{n}h ago",
        agoDays: PluralText(one: "{count} day ago", other: "{count} days ago"), compactMinutes: "{n}m ago",
        compactHours: "{n}h ago", compactDays: "{n}d ago")
}
