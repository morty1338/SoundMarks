import Foundation

/// Request for a yearly "on this day" notification.
///
/// One entry = one calendar day. If there are several places on that day,
/// they are collected in `entries`, and there is still just one notification.
struct OnThisDayNotification: Hashable, Sendable, Identifiable {
    /// One memory on this day.
    struct Entry: Hashable, Sendable {
        let placeID: UUID
        let year: Int
        let placeName: String?
        let trackTitle: String?
        let artist: String?
    }

    let month: Int
    let day: Int
    let entries: [Entry]
    /// Local hour and minute when to show the notification.
    let hour: Int
    let minute: Int

    var id: String { "\(NotificationIdentifier.onThisDayPrefix)\(month)-\(day)" }

    var placeIDs: [UUID] { entries.map(\.placeID) }

    /// iOS keeps no more than 64 scheduled local notifications at a time.
    static let systemPendingLimit = 64

    init(month: Int, day: Int, entries: [Entry], hour: Int = 10, minute: Int = 0) {
        self.month = month
        self.day = day
        self.entries = entries
        self.hour = hour
        self.minute = minute
    }

    /// The next occurrence of this date starting from `date`.
    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.nextDate(after: date,
                                 matching: components,
                                 matchingPolicy: .nextTimePreservingSmallerComponents)
    }
}
