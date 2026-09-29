import Foundation
import Testing

@testable import SoundMarks

/// The "on this day" scheduler must fit within the iOS limit (64 notifications)
/// and return the memories nearest by date.
@Suite("OnThisDayScheduler")
struct OnThisDaySchedulerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)) ?? Date()
    }

    private func place(year: Int, month: Int?, day: Int?,
                       title: String = "Song", name: String? = "Barcelona") -> PlaceSnapshot {
        PlaceSnapshot(
            id: UUID(),
            latitude: 41.38,
            longitude: 2.16,
            placeName: name,
            city: nil, country: nil,
            note: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            eventDate: EventDate(year: year, month: month, day: day),
            pinStyleOverride: nil,
            geofenceEnabled: true,
            trackTitle: title,
            trackArtist: "Artist",
            artworkURL: nil,
            previewURL: nil,
            media: []
        )
    }

    @Test("Places without month and day are not scheduled")
    func skipsImpreciseDates() {
        let places = [
            place(year: 2016, month: nil, day: nil),
            place(year: 2016, month: 8, day: nil),
            place(year: 2016, month: 8, day: 14),
        ]
        let schedule = OnThisDayScheduler.schedule(for: places, now: now, hour: 10, calendar: calendar)
        #expect(schedule.count == 1)
        #expect(schedule.first?.month == 8)
        #expect(schedule.first?.day == 14)
    }

    @Test("Places of the same day are combined into one notification")
    func groupsSameDay() throws {
        let places = [
            place(year: 2019, month: 9, day: 25, title: "A"),
            place(year: 2021, month: 9, day: 25, title: "B"),
            place(year: 2023, month: 9, day: 25, title: "C"),
        ]
        let schedule = OnThisDayScheduler.schedule(for: places, now: now, hour: 10, calendar: calendar)

        #expect(schedule.count == 1)
        let first = try #require(schedule.first)
        #expect(first.entries.count == 3)
        // Within a day — from old memories to new ones.
        #expect(first.entries.map(\.year) == [2019, 2021, 2023])
    }

    @Test("The schedule does not exceed the iOS limit of 64 notifications")
    func respectsSystemLimit() {
        // 100 different days — clearly more than the limit.
        let places = (0..<100).map { offset -> PlaceSnapshot in
            let date = calendar.date(byAdding: .day, value: offset,
                                     to: calendar.date(from: DateComponents(year: 2020, month: 1, day: 1)) ?? Date())
            let parts = calendar.dateComponents([.month, .day], from: date ?? Date())
            return place(year: 2020, month: parts.month, day: parts.day)
        }

        let schedule = OnThisDayScheduler.schedule(for: places, now: now, hour: 10, calendar: calendar)
        #expect(schedule.count == OnThisDayNotification.systemPendingLimit)
        #expect(schedule.count <= 64)
    }

    @Test("The nearest dates are taken, not arbitrary ones")
    func picksNearestDates() throws {
        let places = [
            place(year: 2015, month: 12, day: 31),
            place(year: 2015, month: 1, day: 2),
            place(year: 2015, month: 6, day: 15),
        ]
        let schedule = OnThisDayScheduler.schedule(for: places, now: now, hour: 10, limit: 2, calendar: calendar)

        #expect(schedule.count == 2)
        // Now is January 1, 2026: the nearest are January 2, then June 15.
        #expect(schedule.map { "\($0.month)-\($0.day)" } == ["1-2", "6-15"])
    }

    @Test("A zero limit gives an empty schedule")
    func zeroLimit() {
        let schedule = OnThisDayScheduler.schedule(for: [place(year: 2020, month: 5, day: 5)],
                                                   now: now, hour: 10, limit: 0, calendar: calendar)
        #expect(schedule.isEmpty)
    }

    @Test("An empty list of places gives no notifications")
    func noPlaces() {
        #expect(OnThisDayScheduler.schedule(for: [], now: now, hour: 10, calendar: calendar).isEmpty)
    }

    @Test("The notification identifier is stable and prefixed")
    func stableIdentifiers() throws {
        let schedule = OnThisDayScheduler.schedule(for: [place(year: 2020, month: 3, day: 7)],
                                                   now: now, hour: 9, calendar: calendar)
        let first = try #require(schedule.first)
        #expect(first.id == "\(NotificationIdentifier.onThisDayPrefix)3-7")
        #expect(first.hour == 9)
    }

    @Test("The next occurrence is computed forward from the current moment")
    func nextOccurrenceIsInFuture() throws {
        let notification = OnThisDayNotification(
            month: 9, day: 25,
            entries: [.init(placeID: UUID(), year: 2023, placeName: nil, trackTitle: nil, artist: nil)],
            hour: 10
        )
        let next = try #require(notification.nextOccurrence(after: now, calendar: calendar))
        let parts = calendar.dateComponents([.year, .month, .day], from: next)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 25)
        #expect(next > now)
    }
}
