import Foundation

/// Pure "on this day" scheduling logic: places turn into notification requests
/// that are already trimmed to the iOS limit.
///
/// Pulled out of the service so the algorithm can be tested
/// without UserNotifications.
enum OnThisDayScheduler {
    /// Builds the schedule.
    ///
    /// - Places without a known month and day are skipped: "on this day" is undefined for them.
    /// - Places of the same calendar day are combined into one notification.
    /// - Days are sorted by nearest occurrence, and the first `limit` are taken.
    ///   The rest get into the schedule on the next recompute.
    static func schedule(
        for places: [PlaceSnapshot],
        now: Date = Date(),
        hour: Int,
        minute: Int = 0,
        limit: Int = OnThisDayNotification.systemPendingLimit,
        calendar: Calendar = .current
    ) -> [OnThisDayNotification] {
        guard limit > 0 else { return [] }

        var byDay: [DayKey: [OnThisDayNotification.Entry]] = [:]

        for place in places {
            guard let eventDate = place.eventDate,
                  eventDate.supportsOnThisDay,
                  let month = eventDate.month,
                  let day = eventDate.day
            else { continue }

            let entry = OnThisDayNotification.Entry(
                placeID: place.id,
                year: eventDate.year,
                placeName: place.placeName,
                trackTitle: place.trackTitle,
                artist: place.trackArtist
            )
            byDay[DayKey(month: month, day: day), default: []].append(entry)
        }

        let notifications = byDay.map { key, entries in
            OnThisDayNotification(
                month: key.month,
                day: key.day,
                // Within a day — from old memories to new ones.
                entries: entries.sorted { ($0.year, $0.placeID.uuidString) < ($1.year, $1.placeID.uuidString) },
                hour: hour,
                minute: minute
            )
        }

        return notifications
            .compactMap { notification -> (OnThisDayNotification, Date)? in
                guard let next = notification.nextOccurrence(after: now, calendar: calendar) else { return nil }
                return (notification, next)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.id < rhs.0.id
            }
            .prefix(limit)
            .map(\.0)
    }

    private struct DayKey: Hashable {
        let month: Int
        let day: Int
    }
}
