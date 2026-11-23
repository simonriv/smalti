import Foundation

/// The line printed after a pane's restored scrollback: `── restaurado · 22 nov 23:48 ──`.
public enum RestoreBanner {
    static let months = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

    public static func text(savedAt: Date, calendar: Calendar) -> String {
        let day = calendar.component(.day, from: savedAt)
        let month = months[calendar.component(.month, from: savedAt) - 1]
        return "── restaurado · \(day) \(month) \(ClockTime.text(savedAt, calendar: calendar)) ──"
    }
}
