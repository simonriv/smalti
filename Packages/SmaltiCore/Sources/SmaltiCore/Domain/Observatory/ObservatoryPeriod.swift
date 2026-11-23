import Foundation

/// The span the observatory sums: from a local midnight until now.
public enum ObservatoryPeriod: CaseIterable, Sendable {
    case today, lastSevenDays, lastThirtyDays

    /// The calendar carries the time zone, read again at every refresh.
    public func start(now: Date, calendar: Calendar) -> Date {
        let midnight = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: midnight) ?? midnight
    }

    private var days: Int {
        switch self {
        case .today: 1
        case .lastSevenDays: 7
        case .lastThirtyDays: 30
        }
    }

    public var next: ObservatoryPeriod {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    public var title: String {
        switch self {
        case .today: "Hoy"
        case .lastSevenDays: "7 días"
        case .lastThirtyDays: "30 días"
        }
    }
}
