import Foundation

/// "hoy a las 18:05", "anoche a las 23:48", "ayer a las 14:10" or "el jue 19 a las 09:12": when the last session was
/// saved, for the resume screen ("Cerraste anoche a las 23:48."). Names come from the catalog, independent of the
/// system's locale.
public enum ClosedAtPhrase {
    /// From this hour the day before counts as "anoche".
    static let eveningStartHour = 18

    public static func text(closedAt: Date, now: Date, calendar: Calendar, texts: StatusTexts) -> String {
        let time = ["time": ClockTime.text(closedAt, calendar: calendar)]
        if calendar.isDate(closedAt, inSameDayAs: now) { return texts.closedToday(time) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(closedAt, inSameDayAs: yesterday)
        {
            let isEvening = calendar.component(.hour, from: closedAt) >= eveningStartHour
            return (isEvening ? texts.closedLastNight : texts.closedYesterday)(time)
        }
        let weekday = texts.weekdays[calendar.component(.weekday, from: closedAt) - 1]
        return texts.closedOn([
            "weekday": weekday, "day": String(calendar.component(.day, from: closedAt)), "time": time["time"] ?? "",
        ])
    }
}

/// `HH:mm` with two digits each.
enum ClockTime {
    static func text(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return "\(twoDigits(hour)):\(twoDigits(minute))"
    }

    private static func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
}
