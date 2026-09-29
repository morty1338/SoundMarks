import Foundation

/// Memory date: the year is required, month and day are optional.
///
/// For old memories the user may remember only the year ("summer 2016"),
/// so the precision is stored explicitly instead of being replaced by January 1.
struct EventDate: Hashable, Sendable {
    /// Precision with which the date is known.
    enum Precision: Int, Comparable, Sendable {
        case year = 0
        case month = 1
        case day = 2

        static func < (lhs: Precision, rhs: Precision) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let year: Int
    let month: Int?
    let day: Int?

    /// - Returns: `nil` if the year is out of a reasonable range or the month/day don't exist.
    init?(year: Int, month: Int? = nil, day: Int? = nil) {
        guard Self.plausibleYears.contains(year) else { return nil }
        if let month {
            guard (1...12).contains(month) else { return nil }
        }
        if let day {
            // A day without a month makes no sense.
            guard let month, (1...Self.daysIn(month: month, year: year)).contains(day) else { return nil }
        }
        self.year = year
        self.month = month
        self.day = day
    }

    var precision: Precision {
        if day != nil { .day } else if month != nil { .month } else { .year }
    }

    /// Whether the month and day are known — only such places take part in "on this day" notifications.
    var supportsOnThisDay: Bool { month != nil && day != nil }

    // MARK: - Interval bounds

    /// Start of the interval covered by the date, given its precision.
    func startOfInterval(calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month ?? 1, day: day ?? 1))
    }

    /// The interval covered by the date: a year, a month or a day.
    func interval(calendar: Calendar = .current) -> DateInterval? {
        guard let start = startOfInterval(calendar: calendar) else { return nil }
        let component: Calendar.Component = switch precision {
        case .year: .year
        case .month: .month
        case .day: .day
        }
        guard let end = calendar.date(byAdding: component, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// The date places are sorted by on the timeline.
    func sortDate(calendar: Calendar = .current) -> Date? { startOfInterval(calendar: calendar) }

    // MARK: - Converting from / to a calendar date

    /// A full date with day precision.
    init?(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        self.init(year: year, month: month, day: day)
    }

    // MARK: - Storage in Core Data (0 = "not specified")

    init?(storedYear: Int16, storedMonth: Int16, storedDay: Int16) {
        self.init(year: Int(storedYear),
                  month: storedMonth == 0 ? nil : Int(storedMonth),
                  day: storedDay == 0 ? nil : Int(storedDay))
    }

    var storedYear: Int16 { Int16(clamping: year) }
    var storedMonth: Int16 { Int16(clamping: month ?? 0) }
    var storedDay: Int16 { Int16(clamping: day ?? 0) }

    // MARK: - Helpers

    static let plausibleYears = 1900...2200

    private static func daysIn(month: Int, year: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: start) else { return 31 }
        return range.count
    }
}

extension EventDate: Comparable {
    static func < (lhs: EventDate, rhs: EventDate) -> Bool {
        (lhs.year, lhs.month ?? 0, lhs.day ?? 0) < (rhs.year, rhs.month ?? 0, rhs.day ?? 0)
    }
}

extension EventDate: CustomStringConvertible {
    /// Localized representation respecting precision: "2016", "August 2016", "14 August 2016".
    var description: String { formatted() }

    func formatted(locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        guard let date = startOfInterval(calendar: calendar) else { return String(year) }

        let format: Date.FormatStyle = switch precision {
        case .year: .dateTime.year()
        case .month: .dateTime.year().month(.wide)
        case .day: .dateTime.year().month(.wide).day()
        }
        return date.formatted(format.locale(locale))
    }
}
