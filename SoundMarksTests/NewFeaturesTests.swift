import CoreLocation
import Foundation
import Testing

@testable import SoundMarks

/// Rank grows with the number of places and unlocks skins.
@Suite("Ranks and skins")
struct RankAndSkinTests {
    @Test("Rank thresholds")
    func thresholds() {
        #expect(RankLadder.rank(forPlaceCount: 0).level == 0)
        #expect(RankLadder.rank(forPlaceCount: 4).level == 0)
        #expect(RankLadder.rank(forPlaceCount: 5).level == 1)
        #expect(RankLadder.rank(forPlaceCount: 29).level == 2)
        #expect(RankLadder.rank(forPlaceCount: 500).level == 5)
        #expect(RankLadder.rank(forPlaceCount: 500).nextThreshold == nil)
    }

    @Test("Progress to the next rank")
    func progress() {
        let rank = RankLadder.rank(forPlaceCount: 10)
        #expect(rank.level == 1)
        #expect(rank.progress(placeCount: 10) == 0.5)
    }

    @Test("A beginner has only the basic skins unlocked, exclusive ones from a high rank")
    func unlocks() {
        let rookie = SkinCatalog.unlocked(at: 0).map(\.id)
        #expect(rookie == [SkinCatalog.standardID, "classic"])
        #expect(SkinCatalog.unlocked(at: 5).count == SkinCatalog.all.count)
        #expect(SkinCatalog.all.filter(\.isExclusive).allSatisfy { $0.requiredRank >= RankLadder.exclusiveFrom })
    }

    @Test("An unknown skin is a regular record")
    func unknownSkin() {
        #expect(SkinCatalog.skin(id: "nope").id == SkinCatalog.standardID)
        #expect(SkinCatalog.skin(id: nil).assetName == nil)
    }

    @Test("Every skin except the regular one has an image")
    func assets() {
        #expect(SkinCatalog.all.dropFirst().allSatisfy { $0.assetName != nil })
    }
}

@Suite("Profile stats")
struct ProfileStatsTests {
    private func place(city: String?, country: String?, artist: String, year: Int) -> PlaceSnapshot {
        PlaceSnapshot(id: UUID(), latitude: 0, longitude: 0, placeName: nil, city: city, country: country,
                      note: nil, createdAt: Date(), eventDate: EventDate(year: year),
                      pinStyleOverride: nil, geofenceEnabled: false,
                      trackTitle: "T", trackArtist: artist, artworkURL: nil, previewURL: nil, media: [])
    }

    @Test("Countries and cities are counted without duplicates and case")
    func distinct() {
        let stats = ProfileStats.make(from: [
            place(city: "Berlin", country: "Germany", artist: "A", year: 2020),
            place(city: "berlin", country: "Germany", artist: "B", year: 2018),
            place(city: "Rome", country: "Italy", artist: "A", year: 2022),
            place(city: nil, country: nil, artist: "C", year: 2024),
        ])
        #expect(stats.places == 4)
        #expect(stats.cities == 2)
        #expect(stats.countries == 2)
        #expect(stats.artists == 3)
        #expect(stats.firstYear == 2018)
    }
}

@Suite("The \"All\" strip")
struct NearestOrderingTests {
    private func place(_ latitude: Double, _ longitude: Double) -> PlaceSnapshot {
        PlaceSnapshot(id: UUID(), latitude: latitude, longitude: longitude, placeName: nil, city: nil,
                      country: nil, note: nil, createdAt: Date(), eventDate: EventDate(year: 2024),
                      pinStyleOverride: nil, geofenceEnabled: false,
                      trackTitle: nil, trackArtist: nil, artworkURL: nil, previewURL: nil, media: [])
    }

    @Test("The nearest record comes first")
    func nearestFirst() {
        let berlin = place(52.52, 13.40)
        let munich = place(48.14, 11.58)
        let rome = place(41.90, 12.50)
        let sorted = NearestOrdering.sorted([rome, berlin, munich],
                                            from: CLLocationCoordinate2D(latitude: 48.2, longitude: 11.6))
        #expect(sorted.map(\.id) == [munich.id, berlin.id, rome.id])
    }
}

@Suite("Day and night")
struct DayCycleTests {
    private func date(hour: Int) -> Date {
        var components = DateComponents(year: 2026, month: 9, day: 27, hour: hour)
        components.timeZone = .current
        return Calendar.current.date(from: components) ?? Date()
    }

    @Test("Daytime is from 7 to 20")
    func hours() {
        #expect(!DayCycle.isDay(at: date(hour: 6)))
        #expect(DayCycle.isDay(at: date(hour: 7)))
        #expect(DayCycle.isDay(at: date(hour: 19)))
        #expect(!DayCycle.isDay(at: date(hour: 20)))
        #expect(!DayCycle.isDay(at: date(hour: 0)))
    }
}

@Suite("Exchange file compatibility")
struct SoundmapCompatibilityTests {
    @Test("A place from an old file without a skin is read")
    func missingSkin() throws {
        let json = """
        {"id":"\(UUID().uuidString)","latitude":1,"longitude":2,"createdAt":"2026-01-01T00:00:00Z",
         "updatedAt":"2026-01-01T00:00:00Z","eventYear":2025,"isTombstoned":false,"media":[]}
        """
        let place = try JSONDecoder.soundmap.decode(PlaceDTO.self, from: Data(json.utf8))
        #expect(place.skinID == nil)
    }
}

@Suite("Planet analysis for a period")
struct PlanetAnalysisTests {
    private func place(city: String, artist: String, title: String, year: Int, month: Int) -> PlaceSnapshot {
        PlaceSnapshot(id: UUID(), latitude: 0, longitude: 0, placeName: nil, city: city, country: "DE",
                      note: nil, createdAt: Date(), eventDate: EventDate(year: year, month: month, day: 10),
                      pinStyleOverride: nil, geofenceEnabled: false,
                      trackTitle: title, trackArtist: artist, artworkURL: nil, previewURL: nil, media: [])
    }

    private func year(_ value: Int) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: value, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: value + 1, month: 1, day: 1)) ?? Date()
        return DateInterval(start: start, end: end.addingTimeInterval(-1))
    }

    @Test("Only places within the period are counted; tops by frequency")
    func periodAndTops() {
        let places = [
            place(city: "Berlin", artist: "Daft Punk", title: "One More Time", year: 2023, month: 5),
            place(city: "Berlin", artist: "Daft Punk", title: "Get Lucky", year: 2023, month: 5),
            place(city: "Hamburg", artist: "Moderat", title: "A New Error", year: 2023, month: 8),
            place(city: "Rome", artist: "Daft Punk", title: "Veridis Quo", year: 2021, month: 1),
        ]
        let report = PlanetAnalysis.report(places: places, plays: [], interval: year(2023))
        #expect(report.places == 3)
        #expect(report.cities == 2)
        #expect(report.topCities.first == .init(name: "Berlin", count: 2))
        #expect(report.topArtists.first == .init(name: "Daft Punk", count: 2))
        #expect(report.busiestMonth == DateComponents(year: 2023, month: 5))
    }

    @Test("Listening history for the same period, short plays are not counted")
    func history() {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2023, month: 6, day: 1)) ?? Date()
        let plays = [
            PlayRecord(playedAt: date, title: "A", artist: "X", playedDuration: .seconds(3600), source: .spotifyExport),
            PlayRecord(playedAt: date, title: "B", artist: "X", playedDuration: .seconds(10), source: .spotifyExport),
            PlayRecord(playedAt: date.addingTimeInterval(-400 * 86400), title: "C", artist: "Y",
                       playedDuration: .seconds(3600), source: .spotifyExport),
        ]
        let report = PlanetAnalysis.report(places: [], plays: plays, interval: year(2023))
        #expect(report.plays == 1)
        #expect(report.listeningHours == 1)
        #expect(report.historyTopArtists == [.init(name: "X", count: 1)])
        #expect(!report.isEmpty)
    }
}

@Suite("Promo codes")
@MainActor
struct PromoCodeTests {
    @Test("PENIS unlocks all skins, case and spaces do not matter")
    func unlocksAllSkins() throws {
        let defaults = try #require(UserDefaults(suiteName: "promo-\(UUID().uuidString)"))
        let settings = AppSettings(defaults: defaults)
        let rookie = RankLadder.rank(forPlaceCount: 0)
        #expect(settings.skinUnlockLevel(for: rookie) == 0)
        #expect(settings.redeem("nope") == nil)
        #expect(settings.redeem("  penis ") == .allSkins)
        #expect(settings.allSkinsUnlocked)
        #expect(SkinCatalog.unlocked(at: settings.skinUnlockLevel(for: rookie)).count == SkinCatalog.all.count)
        // Persists between launches.
        #expect(AppSettings(defaults: defaults).allSkinsUnlocked)
    }
}
