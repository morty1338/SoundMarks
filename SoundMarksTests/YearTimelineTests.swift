import Foundation
import Testing

@testable import SoundMarks

/// Vertical timeline: the map shows places up to and including the selected year.
@Suite("YearTimeline")
@MainActor
struct YearTimelineTests {
    private func place(year: Int?) -> PlaceSnapshot {
        PlaceSnapshot(
            id: UUID(), latitude: 0, longitude: 0,
            placeName: nil, city: nil, country: nil, note: nil, createdAt: Date(),
            eventDate: year.flatMap { EventDate(year: $0) },
            pinStyleOverride: nil, geofenceEnabled: true,
            trackTitle: "T", trackArtist: "A", artworkURL: nil, previewURL: nil, media: []
        )
    }

    @Test("The filter includes the selected year")
    func includesSelectedYear() {
        let places = [place(year: 2019), place(year: 2021), place(year: 2023)]
        let visible = YearTimeline.visible(places, upTo: 2021)
        #expect(visible.compactMap { $0.eventDate?.year } == [2019, 2021])
    }

    @Test("Places without a date are visible for any year")
    func undatedAlwaysVisible() {
        let undated = place(year: nil)
        #expect(YearTimeline.visible([undated, place(year: 2024)], upTo: 2000).count == 1)
    }

    @Test("The top of the scale is the current year, the bottom is the earliest memory")
    func scaleSpansToCurrentYear() {
        let timeline = YearTimeline(currentYear: 2026)
        timeline.rebuild(from: [place(year: 2019), place(year: 2023)])
        #expect(timeline.years.first == 2026)
        #expect(timeline.years.last == 2019)
        #expect(timeline.years.count == 8)
        #expect(timeline.showsEverything)
    }

    @Test("Future dates do not raise the top of the scale")
    func futureDatesDoNotExtend() {
        let timeline = YearTimeline(currentYear: 2026)
        timeline.rebuild(from: [place(year: 2030)])
        #expect(timeline.years == [2026])
    }

    @Test("In the top position everything is visible, including future dates")
    func topShowsEverything() {
        let timeline = YearTimeline(currentYear: 2026)
        let places = [place(year: 2019), place(year: 2030)]
        timeline.rebuild(from: places)
        #expect(timeline.filter(places).count == 2)
    }

    @Test("A step down — an earlier year; the year change is reported for haptics")
    func steppingDown() {
        let timeline = YearTimeline(currentYear: 2026)
        let places = [place(year: 2020), place(year: 2024)]
        timeline.rebuild(from: places)

        #expect(timeline.select(index: 2))
        #expect(timeline.selectedYear == 2024)
        #expect(timeline.filter(places).count == 2)

        #expect(timeline.select(index: 2) == false)

        timeline.select(index: 5)
        #expect(timeline.selectedYear == 2021)
        #expect(timeline.filter(places).count == 1)
    }

    @Test("The index does not go beyond the scale")
    func clamped() {
        let timeline = YearTimeline(currentYear: 2026)
        timeline.rebuild(from: [place(year: 2024)])
        timeline.select(index: 99)
        #expect(timeline.selectedYear == 2024)
        timeline.select(index: -5)
        #expect(timeline.selectedYear == 2026)
    }

    @Test("A new place does not reset the selected year")
    func rebuildKeepsSelection() {
        let timeline = YearTimeline(currentYear: 2026)
        timeline.rebuild(from: [place(year: 2018)])
        timeline.select(index: 3) // 2023
        timeline.rebuild(from: [place(year: 2015), place(year: 2018)])
        #expect(timeline.selectedYear == 2023)
    }
}
