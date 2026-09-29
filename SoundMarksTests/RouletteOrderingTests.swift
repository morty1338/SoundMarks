import Foundation
import Testing

@testable import SoundMarks

/// Record order in the roulette.
@Suite("RouletteOrdering")
struct RouletteOrderingTests {
    private func place(_ title: String, year: Int, month: Int = 6, country: String? = nil) -> PlaceSnapshot {
        PlaceSnapshot(
            id: UUID(), latitude: 0, longitude: 0,
            placeName: nil, city: nil, country: country, note: nil, createdAt: Date(),
            eventDate: EventDate(year: year, month: month, day: 1),
            pinStyleOverride: nil, geofenceEnabled: true,
            trackTitle: title, trackArtist: "A", artworkURL: nil, previewURL: nil, media: []
        )
    }

    @Test("By date — newest first")
    func byDate() {
        let places = [place("old", year: 2016), place("new", year: 2024), place("mid", year: 2020)]
        let ordered = RouletteOrdering.ordered(places, by: .date)
        #expect(ordered.map(\.displayTitle) == ["new", "mid", "old"])
    }

    @Test("By country — alphabetical, newest to oldest within a country, no country — at the end")
    func byCountry() {
        let places = [
            place("es-old", year: 2016, country: "Spanien"),
            place("none", year: 2025),
            place("de", year: 2020, country: "Deutschland"),
            place("es-new", year: 2023, country: "Spanien"),
        ]
        let ordered = RouletteOrdering.ordered(places, by: .country)
        #expect(ordered.map(\.displayTitle) == ["de", "es-new", "es-old", "none"])
    }

    @Test("Group caption: country or year")
    func groupCaptions() {
        let berlin = place("x", year: 2021, country: "Deutschland")
        #expect(RouletteOrdering.group(of: berlin, by: .country) == "Deutschland")
        #expect(RouletteOrdering.group(of: berlin, by: .year) == "2021")
        #expect(RouletteOrdering.group(of: berlin, by: .date) == nil)
    }

    @Test("The date above the record respects precision")
    func compactDate() {
        let full = place("x", year: 2026, month: 9)
        #expect(full.compactDate == "01.09.2026")
    }
}

/// The record in the center of the roulette starts spinning only after 5 seconds.
@Suite("Record spin in the roulette")
@MainActor
struct RouletteSpinTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test("For the first 5 seconds the record stands still")
    func stillForFiveSeconds() {
        #expect(RouletteView.spinAngle(since: start, now: start) == 0)
        #expect(RouletteView.spinAngle(since: start, now: start.addingTimeInterval(4.99)) == 0)
    }

    @Test("After 5 seconds — a smooth ramp-up, then one turn per 12 seconds")
    func spinsAfterDelay() {
        let early = RouletteView.spinAngle(since: start, now: start.addingTimeInterval(5.5))
        #expect(early > 0 && early < 15)

        let a = RouletteView.spinAngle(since: start, now: start.addingTimeInterval(10))
        let b = RouletteView.spinAngle(since: start, now: start.addingTimeInterval(22))
        #expect(abs((b - a) - 360) < 0.001)
    }
}
