import Foundation
import Testing

@testable import SoundMarks

/// The short play filter — part of the track ↔ photo matching algorithm.
@Suite("PlayRecord")
struct PlayRecordTests {
    private func record(playedFor duration: Duration?) -> PlayRecord {
        PlayRecord(playedAt: Date(timeIntervalSince1970: 1_692_000_000),
                   title: "Song",
                   artist: "Artist",
                   playedDuration: duration,
                   source: .spotifyExport)
    }

    @Test("A play shorter than 30 seconds is not significant")
    func shortPlaybackIsIgnored() {
        #expect(record(playedFor: .seconds(29)).isMeaningfulPlayback == false)
        #expect(record(playedFor: .milliseconds(1)).isMeaningfulPlayback == false)
    }

    @Test("Exactly 30 seconds is significant")
    func exactThresholdIsMeaningful() {
        #expect(record(playedFor: .seconds(30)).isMeaningfulPlayback)
    }

    @Test("A source without durations counts as significant")
    func unknownDurationIsMeaningful() {
        #expect(record(playedFor: nil).isMeaningfulPlayback)
    }

    @Test("The track key does not depend on case")
    func trackKeyIsCaseInsensitive() {
        let lower = PlayRecord(playedAt: .now, title: "song", artist: "artist", source: .lastFm)
        let upper = PlayRecord(playedAt: .now, title: "SONG", artist: "Artist", source: .lastFm)
        #expect(lower.trackKey == upper.trackKey)
    }
}
