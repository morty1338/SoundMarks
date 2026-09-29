import CoreLocation
import Foundation
import Testing

@testable import SoundMarks

/// Travel mode: during a trip only the route is recorded,
/// tracks are recovered from history timestamps.
@Suite("TripMatcher")
struct TripMatcherTests {
    private let start = Date(timeIntervalSince1970: 1_750_000_000)

    private func sample(_ minutes: Double, _ latitude: Double, _ longitude: Double) -> RouteSample {
        RouteSample(latitude: latitude, longitude: longitude, timestamp: start.addingTimeInterval(minutes * 60))
    }

    private func play(_ minutes: Double, _ title: String, seconds: Int = 180) -> PlayRecord {
        PlayRecord(playedAt: start.addingTimeInterval(minutes * 60), title: title, artist: "Artist",
                   playedDuration: .seconds(seconds), source: .spotifyExport)
    }

    private func photo(_ minutes: Double, _ latitude: Double?, _ longitude: Double?) -> PhotoAssetSnapshot {
        PhotoAssetSnapshot(id: UUID().uuidString, kind: .photo,
                           creationDate: start.addingTimeInterval(minutes * 60),
                           latitude: latitude, longitude: longitude)
    }

    // MARK: - Position by time

    @Test("Between route points the position is interpolated")
    func interpolatesBetweenPoints() throws {
        let route = [sample(0, 50, 10), sample(60, 51, 12)]
        let middle = try #require(TripMatcher.position(at: start.addingTimeInterval(30 * 60), on: route))
        #expect(abs(middle.latitude - 50.5) < 0.0001)
        #expect(abs(middle.longitude - 11) < 0.0001)
    }

    @Test("Before the start and after the end — the outermost route points")
    func clampsToEnds() throws {
        let route = [sample(10, 50, 10), sample(20, 51, 11)]
        let before = try #require(TripMatcher.position(at: start, on: route))
        let after = try #require(TripMatcher.position(at: start.addingTimeInterval(3600), on: route))
        #expect(before.latitude == 50)
        #expect(after.latitude == 51)
    }

    @Test("The order of points does not matter")
    func unsortedRoute() throws {
        let route = [sample(60, 51, 12), sample(0, 50, 10)]
        let middle = try #require(TripMatcher.position(at: start.addingTimeInterval(30 * 60), on: route))
        #expect(abs(middle.latitude - 50.5) < 0.0001)
    }

    @Test("Without a route there is no position")
    func emptyRoute() {
        #expect(TripMatcher.position(at: start, on: []) == nil)
    }

    // MARK: - Route recording

    @Test("A point is recorded after 150 m or 15 minutes")
    func recordingThreshold() {
        let last = sample(0, 50, 10)
        let near = LocationFix(latitude: 50.0005, longitude: 10, horizontalAccuracy: 50,
                               timestamp: start.addingTimeInterval(60))
        let far = LocationFix(latitude: 50.01, longitude: 10, horizontalAccuracy: 50,
                              timestamp: start.addingTimeInterval(60))
        let later = LocationFix(latitude: 50.0005, longitude: 10, horizontalAccuracy: 50,
                                timestamp: start.addingTimeInterval(16 * 60))
        let older = LocationFix(latitude: 51, longitude: 10, horizontalAccuracy: 50,
                                timestamp: start.addingTimeInterval(-60))

        #expect(TripMatcher.shouldRecord(near, after: nil))
        #expect(!TripMatcher.shouldRecord(near, after: last))
        #expect(TripMatcher.shouldRecord(far, after: last))
        #expect(TripMatcher.shouldRecord(later, after: last))
        #expect(!TripMatcher.shouldRecord(older, after: last))
    }

    // MARK: - Stops

    @Test("Tracks close in time and place form one stop, distant ones form different stops")
    func groupsStops() {
        // Half an hour in place, then an hour and a half on the road: ~111 km per degree of latitude.
        let route = [sample(0, 50, 10), sample(30, 50, 10), sample(120, 51, 10)]
        let plays = [play(0, "A"), play(4, "B"), play(110, "C")]
        let stops = TripMatcher.stops(route: route, plays: plays, photos: [])
        #expect(stops.count == 2)
        #expect(stops.first?.plays.map(\.title) == ["A", "B"])
        #expect(stops.last?.plays.map(\.title) == ["C"])
    }

    @Test("A repeated track in a stop and short plays are dropped")
    func dedupesAndSkipsShortPlays() {
        let route = [sample(0, 50, 10)]
        let plays = [play(0, "A"), play(3, "A"), play(5, "Skip", seconds: 10), play(6, "B")]
        let stops = TripMatcher.stops(route: route, plays: plays, photos: [])
        #expect(stops.count == 1)
        #expect(stops.first?.plays.map(\.title) == ["A", "B"])
    }

    @Test("A geotagged photo close in time is more precise than the route")
    func photoLocationWins() throws {
        let route = [sample(0, 50, 10), sample(60, 51, 10)]
        let stops = TripMatcher.stops(route: route,
                                      plays: [play(30, "A")],
                                      photos: [photo(32, 48.8566, 2.3522), photo(90, nil, nil)])
        let stop = try #require(stops.first)
        #expect(abs(stop.latitude - 48.8566) < 0.0001)
        // A photo without a geotag outside the window isn't included, inside the window it is.
        #expect(stop.photos.count == 1)
    }

    @Test("Without a route and photos a track cannot be placed")
    func noLocationNoStop() {
        #expect(TripMatcher.stops(route: [], plays: [play(0, "A")], photos: []).isEmpty)
    }
}
