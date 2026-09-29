import CoreLocation
import Foundation
import Testing

@testable import SoundMarks

/// "Track ↔ photo" matching: a ±30 minute window, grouping shots,
/// filtering short plays.
@Suite("MemoryMatcher")
struct MemoryMatcherTests {
    private let barcelona = CLLocationCoordinate2D(latitude: 41.3874, longitude: 2.1686)

    private func date(_ offsetMinutes: Double) -> Date {
        Date(timeIntervalSince1970: 1_692_000_000).addingTimeInterval(offsetMinutes * 60)
    }

    private func photo(minutes: Double,
                       coordinate: CLLocationCoordinate2D? = nil,
                       id: String = UUID().uuidString) -> PhotoAssetSnapshot {
        let target = coordinate ?? barcelona
        return PhotoAssetSnapshot(id: id,
                                  kind: .photo,
                                  creationDate: date(minutes),
                                  latitude: target.latitude,
                                  longitude: target.longitude)
    }

    private func play(minutes: Double,
                      title: String = "Song",
                      artist: String = "Artist",
                      duration: Duration? = .seconds(180)) -> PlayRecord {
        PlayRecord(playedAt: date(minutes),
                   title: title,
                   artist: artist,
                   playedDuration: duration,
                   source: .spotifyExport)
    }

    // MARK: - Matching window

    @Test("A track inside the ±30 minute window becomes part of the candidate")
    func trackInsideWindowMatches() throws {
        let candidates = MemoryMatcher.candidates(photos: [photo(minutes: 0)],
                                                  plays: [play(minutes: 25)])
        #expect(candidates.count == 1)
        #expect(try #require(candidates.first).trackOptions.count == 1)
    }

    @Test("A track outside the window is not included")
    func trackOutsideWindowIsIgnored() {
        let candidates = MemoryMatcher.candidates(photos: [photo(minutes: 0)],
                                                  plays: [play(minutes: 31)])
        #expect(candidates.isEmpty)
    }

    @Test("The window boundary is inclusive")
    func windowBoundaryIsInclusive() {
        let candidates = MemoryMatcher.candidates(photos: [photo(minutes: 0)],
                                                  plays: [play(minutes: 30)])
        #expect(candidates.count == 1)
    }

    @Test("The window is configurable")
    func windowIsConfigurable() {
        var options = MemoryMatcher.Options()
        options.window = .seconds(5 * 60)

        #expect(MemoryMatcher.candidates(photos: [photo(minutes: 0)],
                                         plays: [play(minutes: 25)],
                                         options: options).isEmpty)

        options.window = .seconds(60 * 60)
        #expect(MemoryMatcher.candidates(photos: [photo(minutes: 0)],
                                         plays: [play(minutes: 45)],
                                         options: options).count == 1)
    }

    @Test("The window is measured from the edges of the shoot, not from its middle")
    func windowExtendsFromClusterEdges() {
        // A shoot from minute 0 to 20; a track at minute 48 is 28 minutes after the end.
        let photos = [photo(minutes: 0), photo(minutes: 20)]
        #expect(MemoryMatcher.candidates(photos: photos, plays: [play(minutes: 48)]).count == 1)
    }

    // MARK: - Short play filter

    @Test("A play shorter than 30 seconds does not create a candidate")
    func shortPlaybackIsFilteredOut() {
        let candidates = MemoryMatcher.candidates(
            photos: [photo(minutes: 0)],
            plays: [play(minutes: 5, duration: .seconds(29))]
        )
        #expect(candidates.isEmpty)
    }

    @Test("Exactly 30 seconds counts")
    func exactThresholdCounts() {
        let candidates = MemoryMatcher.candidates(
            photos: [photo(minutes: 0)],
            plays: [play(minutes: 5, duration: .seconds(30))]
        )
        #expect(candidates.count == 1)
    }

    @Test("A source without durations is not discarded")
    func unknownDurationCounts() {
        let candidates = MemoryMatcher.candidates(
            photos: [photo(minutes: 0)],
            plays: [play(minutes: 5, duration: nil)]
        )
        #expect(candidates.count == 1)
    }

    // MARK: - Grouping shots

    @Test("Shots close in time and place form one group")
    func nearbyPhotosFormOneCluster() throws {
        let photos = [photo(minutes: 0), photo(minutes: 10), photo(minutes: 25)]
        let clusters = MemoryMatcher.cluster(photos: photos)
        #expect(clusters.count == 1)
        #expect(try #require(clusters.first).photos.count == 3)
    }

    @Test("A time gap splits shots into groups")
    func timeGapSplitsClusters() {
        let photos = [photo(minutes: 0), photo(minutes: 10), photo(minutes: 200)]
        let clusters = MemoryMatcher.cluster(photos: photos)
        #expect(clusters.count == 2)
        #expect(clusters.map(\.photos.count) == [2, 1])
    }

    @Test("A different place splits shots into groups")
    func distanceSplitsClusters() {
        let elsewhere = CLLocationCoordinate2D(latitude: 41.4036, longitude: 2.1744) // ~2 km
        let photos = [photo(minutes: 0), photo(minutes: 5, coordinate: elsewhere)]
        #expect(MemoryMatcher.cluster(photos: photos).count == 2)
    }

    @Test("Shots without a geotag are skipped")
    func photosWithoutLocationAreSkipped() {
        let noLocation = PhotoAssetSnapshot(id: "x", kind: .photo,
                                            creationDate: date(0),
                                            latitude: nil, longitude: nil)
        #expect(MemoryMatcher.cluster(photos: [noLocation]).isEmpty)
        #expect(MemoryMatcher.candidates(photos: [noLocation], plays: [play(minutes: 0)]).isEmpty)
    }

    @Test("The group center is the average of the shots")
    func clusterCentroid() throws {
        let second = CLLocationCoordinate2D(latitude: 41.3884, longitude: 2.1696)
        let clusters = MemoryMatcher.cluster(photos: [photo(minutes: 0),
                                                      photo(minutes: 5, coordinate: second)])
        let cluster = try #require(clusters.first)
        #expect(abs(cluster.latitude - (41.3874 + 41.3884) / 2) < 0.0001)
        #expect(abs(cluster.longitude - (2.1686 + 2.1696) / 2) < 0.0001)
    }

    // MARK: - Track options

    @Test("Options are sorted by proximity to the middle of the shoot")
    func trackOptionsAreRankedByCloseness() throws {
        let candidates = MemoryMatcher.candidates(
            photos: [photo(minutes: 0)],
            plays: [play(minutes: -20, title: "Far"),
                    play(minutes: 3, title: "Near"),
                    play(minutes: 12, title: "Middle")]
        )
        let candidate = try #require(candidates.first)
        #expect(candidate.trackOptions.map(\.title) == ["Near", "Middle", "Far"])
        #expect(candidate.selectedTrack?.title == "Near")
    }

    @Test("The same track in the window is not duplicated")
    func repeatedTrackAppearsOnce() throws {
        let candidates = MemoryMatcher.candidates(
            photos: [photo(minutes: 0)],
            plays: [play(minutes: -25, title: "Loop"),
                    play(minutes: 2, title: "Loop"),
                    play(minutes: 20, title: "Loop")]
        )
        let candidate = try #require(candidates.first)
        #expect(candidate.trackOptions.count == 1)
        // The play closest to the shoot remains.
        #expect(candidate.trackOptions.first?.playedAt == date(2))
    }

    @Test("The number of options is limited")
    func trackOptionsAreLimited() throws {
        var options = MemoryMatcher.Options()
        options.maximumTrackOptions = 2

        let plays = (1...6).map { play(minutes: Double($0), title: "Track \($0)") }
        let candidates = MemoryMatcher.candidates(photos: [photo(minutes: 0)],
                                                  plays: plays,
                                                  options: options)
        #expect(try #require(candidates.first).trackOptions.count == 2)
    }

    @Test("A group without matching tracks is not included in the result")
    func clusterWithoutMatchesIsDropped() {
        let photos = [photo(minutes: 0), photo(minutes: 500)]
        let candidates = MemoryMatcher.candidates(photos: photos, plays: [play(minutes: 5)])
        #expect(candidates.count == 1)
        #expect(candidates.first?.cluster.photos.count == 1)
    }

    @Test("The memory date is taken from the day of the shoot")
    func candidateEventDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let candidate = try #require(
            MemoryMatcher.candidates(photos: [photo(minutes: 0)], plays: [play(minutes: 0)]).first
        )
        let eventDate = try #require(candidate.eventDate(calendar: calendar))
        #expect(eventDate.precision == .day)
        #expect(eventDate.supportsOnThisDay)
    }

    @Test("Empty input does not crash")
    func emptyInputs() {
        #expect(MemoryMatcher.candidates(photos: [], plays: []).isEmpty)
        #expect(MemoryMatcher.candidates(photos: [photo(minutes: 0)], plays: []).isEmpty)
        #expect(MemoryMatcher.candidates(photos: [], plays: [play(minutes: 0)]).isEmpty)
    }
}
