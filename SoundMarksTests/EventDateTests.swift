import Foundation
import Testing

@testable import SoundMarks

/// Checks that the precision of a memory date is not replaced with January 1.
@Suite("EventDate")
struct EventDateTests {
    @Test("A year without month and day is allowed and has .year precision")
    func yearOnly() throws {
        let date = try #require(EventDate(year: 2016))
        #expect(date.precision == .year)
        #expect(date.supportsOnThisDay == false)
    }

    @Test("A day without a month is rejected")
    func dayWithoutMonth() {
        #expect(EventDate(year: 2016, month: nil, day: 14) == nil)
    }

    @Test("A nonexistent date is rejected")
    func impossibleDates() {
        #expect(EventDate(year: 2023, month: 2, day: 30) == nil)
        #expect(EventDate(year: 2023, month: 13) == nil)
        #expect(EventDate(year: 1800) == nil)
    }

    @Test("February 29 is accepted in a leap year and rejected in a common year")
    func leapDay() {
        #expect(EventDate(year: 2024, month: 2, day: 29) != nil)
        #expect(EventDate(year: 2023, month: 2, day: 29) == nil)
    }

    @Test("A full date supports \"on this day\" notifications")
    func fullDate() throws {
        let date = try #require(EventDate(year: 2023, month: 9, day: 25))
        #expect(date.precision == .day)
        #expect(date.supportsOnThisDay)
    }

    @Test("Precision survives a round trip through Core Data")
    func roundTripThroughStorage() throws {
        let cases = try [
            #require(EventDate(year: 2016)),
            #require(EventDate(year: 2016, month: 8)),
            #require(EventDate(year: 2016, month: 8, day: 14)),
        ]
        for original in cases {
            let restored = EventDate(storedYear: original.storedYear,
                                     storedMonth: original.storedMonth,
                                     storedDay: original.storedDay)
            #expect(restored == original)
        }
    }

    @Test("The interval matches the precision")
    func intervalMatchesPrecision() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let year = try #require(EventDate(year: 2023))
        let yearInterval = try #require(year.interval(calendar: calendar))
        #expect(yearInterval.duration == 365 * 24 * 3600)

        let day = try #require(EventDate(year: 2023, month: 9, day: 25))
        let dayInterval = try #require(day.interval(calendar: calendar))
        #expect(dayInterval.duration == 24 * 3600)
    }

    @Test("Sorting goes from oldest to newest")
    func ordering() throws {
        let older = try #require(EventDate(year: 2016, month: 8))
        let newer = try #require(EventDate(year: 2016, month: 9))
        #expect(older < newer)
    }
}
