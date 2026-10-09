import Foundation

/// Link to a track in Spotify.
///
/// `open.spotify.com` is a universal link: with Spotify installed it opens the app,
/// otherwise the web player. No URL scheme query and no Info.plist entry needed.
enum SpotifyLink {
    /// The track itself when the export gave its URI, otherwise a search for "artist title".
    static func url(for play: PlayRecord) -> URL? {
        if let id = trackID(from: play.spotifyURI) {
            return URL(string: "https://open.spotify.com/track/\(id)")
        }
        let query = "\(play.artist) \(play.title)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed
                .subtracting(CharacterSet(charactersIn: "/?#")))
        else { return nil }
        return URL(string: "https://open.spotify.com/search/\(encoded)")
    }

    /// `spotify:track:2cGxRwrMyEAp8dEbuZaVv6` → `2cGxRwrMyEAp8dEbuZaVv6`.
    static func trackID(from uri: String?) -> String? {
        guard let uri else { return nil }
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", parts[1] == "track",
              parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
        return String(parts[2])
    }
}
