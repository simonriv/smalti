import Foundation

/// The observatory's numbers as the board writes them: decimal point, "k" and "M", "1h 12m", "hace 3h".
public enum ObservatoryFormat {
    private static let thousand = 1_000
    private static let million = 1_000_000
    private static let oneDecimalLimit = 100_000

    /// `412`, `61.4k`, `982k`, `1.24M`.
    public static func count(_ value: Int) -> String {
        if value < thousand { return String(value) }
        // Below 100k the tenths are at most 100.0, which reads "100k" either way.
        if value < oneDecimalLimit {
            return decimal(rounded(Double(value) / Double(thousand), places: 1), places: 1) + "k"
        }
        let thousands = (Double(value) / Double(thousand)).rounded()
        if thousands < Double(thousand) { return String(Int(thousands)) + "k" }
        return decimal(rounded(Double(value) / Double(million), places: 2), places: 2) + "M"
    }

    private static let secondsPerMinute = 60
    private static let minutesPerHour = 60
    private static let secondsPerHour = 3_600
    private static let secondsPerDay = 86_400

    /// `34m`, `1h 12m`, `2h 05m`.
    public static func lifetime(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds)) / secondsPerMinute
        let hours = minutes / minutesPerHour
        guard hours > 0 else { return "\(minutes)m" }
        return "\(hours)h \(twoDigits(minutes % minutesPerHour))m"
    }

    /// `hace 22 min` under an hour, `hace 3h` under a day, `hace 2 días` after.
    public static func ago(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        if whole < secondsPerHour { return "hace \(whole / secondsPerMinute) min" }
        if whole < secondsPerDay { return "hace \(whole / secondsPerHour)h" }
        let days = whole / secondsPerDay
        return "hace \(days) \(days == 1 ? "día" : "días")"
    }

    /// Memory is counted in binary units, as Activity Monitor does, and written "GB" as macOS writes it.
    /// `hace 22m`, `hace 3h`, `hace 2d`: the sessions table's 76 pt "Vida" column, where "hace 22 min" truncates.
    public static func agoCompact(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        if whole < secondsPerHour { return "hace \(whole / secondsPerMinute)m" }
        if whole < secondsPerDay { return "hace \(whole / secondsPerHour)h" }
        return "hace \(whole / secondsPerDay)d"
    }

    private static let bytesPerGibibyte = 1_073_741_824.0
    private static let bytesPerMebibyte = 1_048_576.0

    /// `6.1 GB`, or `274 MB` under a gigabyte.
    public static func gigabytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value < bytesPerGibibyte { return "\(Int((value / bytesPerMebibyte).rounded())) MB" }
        return gigabyteNumber(bytes) + " GB"
    }

    /// `6.1`: gigabytes with one decimal, no unit.
    public static func gigabyteNumber(_ bytes: UInt64) -> String {
        decimal(rounded(Double(bytes) / bytesPerGibibyte, places: 1), places: 1, keepZero: true)
    }

    /// `11.2 / 16 GB`: the installed memory is a whole number of gigabytes.
    public static func memory(used: UInt64, total: UInt64) -> String {
        "\(gigabyteNumber(used)) / \(Int((Double(total) / bytesPerGibibyte).rounded())) GB"
    }

    /// `$18.40`.
    public static func usd(_ value: Double) -> String {
        "$" + decimal(rounded(value, places: 2), places: 2, keepZero: true)
    }

    /// `41%`.
    public static func percent(_ value: Int) -> String { "\(value)%" }

    /// `10:42` in the given zone.
    public static func clock(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return ClockTime.text(date, calendar: calendar)
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }

    /// Fixed decimals with a point; trailing zeros dropped unless `keepZero` (money and memory keep them).
    private static func decimal(_ value: Double, places: Int, keepZero: Bool = false) -> String {
        let scale = Int(pow(10, Double(places)))
        let scaled = Int((value * Double(scale)).rounded())
        let whole = scaled / scale
        var fraction = String(scaled % scale)
        fraction = String(repeating: "0", count: places - fraction.count) + fraction
        if !keepZero { while fraction.hasSuffix("0") { fraction.removeLast() } }
        return fraction.isEmpty ? String(whole) : "\(whole).\(fraction)"
    }

    private static func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }
}
