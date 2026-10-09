import Foundation
import Testing

@testable import SoundMarks

/// "Listen on Spotify" link: the track itself by URI, otherwise a search.
@Suite("SpotifyLink")
struct SpotifyLinkTests {
    private func play(uri: String?, title: String = "Instant Crush", artist: String = "Daft Punk") -> PlayRecord {
        PlayRecord(playedAt: Date(timeIntervalSince1970: 0),
                   title: title,
                   artist: artist,
                   album: nil,
                   playedDuration: nil,
                   spotifyURI: uri,
                   source: .spotifyExport)
    }

    @Test("A track URI opens the track")
    func trackURI() {
        let url = SpotifyLink.url(for: play(uri: "spotify:track:2cGxRwrMyEAp8dEbuZaVv6"))
        #expect(url?.absoluteString == "https://open.spotify.com/track/2cGxRwrMyEAp8dEbuZaVv6")
    }

    @Test("Without a URI — a search for artist and title")
    func searchWithoutURI() {
        let url = SpotifyLink.url(for: play(uri: nil, title: "Get Lucky / Radio Edit"))
        #expect(url?.absoluteString == "https://open.spotify.com/search/Daft%20Punk%20Get%20Lucky%20%2F%20Radio%20Edit")
    }

    @Test("Not a track URI (episode, garbage) falls back to search")
    func otherURIs() {
        #expect(SpotifyLink.trackID(from: "spotify:episode:abc") == nil)
        #expect(SpotifyLink.trackID(from: "spotify:track:ab/cd") == nil)
        #expect(SpotifyLink.trackID(from: nil) == nil)
        let url = SpotifyLink.url(for: play(uri: "spotify:episode:abc"))
        #expect(url?.absoluteString.hasPrefix("https://open.spotify.com/search/") == true)
    }

    @Test("Cyrillic titles are encoded")
    func cyrillic() throws {
        let url = try #require(SpotifyLink.url(for: play(uri: nil, title: "Стефанія", artist: "Kalush")))
        #expect(url.absoluteString.hasPrefix("https://open.spotify.com/search/Kalush%20"))
        #expect(url.absoluteString.contains("%D0%A1"))
    }
}
