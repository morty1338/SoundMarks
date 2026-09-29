import Foundation

/// Where the listening information came from.
enum MusicSourceKind: String, CaseIterable, Sendable, Identifiable, Codable {
    /// Import of Extended Streaming History from Spotify's data export (no API).
    case spotifyExport
    /// Last.fm `user.getRecentTracks`.
    case lastFm
    /// Spotify Web API (`currently-playing` / `recently-played`) — only behind a feature flag.
    case spotifyWebAPI
    /// MusicKit / Apple Music.
    case appleMusic
    /// The user picked the track manually.
    case manual

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .spotifyExport: String(localized: "musicSource.spotifyExport", defaultValue: "Spotify history (file)")
        case .lastFm: String(localized: "musicSource.lastFm", defaultValue: "Last.fm")
        case .spotifyWebAPI: String(localized: "musicSource.spotifyWebAPI", defaultValue: "Spotify Web API")
        case .appleMusic: String(localized: "musicSource.appleMusic", defaultValue: "Apple Music")
        case .manual: String(localized: "musicSource.manual", defaultValue: "Manual")
        }
    }

    /// Whether the source can report "what is playing now".
    var supportsNowPlaying: Bool {
        switch self {
        case .lastFm, .spotifyWebAPI, .appleMusic: true
        case .spotifyExport, .manual: false
        }
    }

    /// Whether the source can provide history with timestamps.
    var supportsHistory: Bool {
        switch self {
        case .spotifyExport, .lastFm, .spotifyWebAPI, .appleMusic: true
        case .manual: false
        }
    }
}
