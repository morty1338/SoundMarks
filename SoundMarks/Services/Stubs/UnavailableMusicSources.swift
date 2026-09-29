import Foundation

/// Spotify Web API (`currently-playing`, `recently-played`). Implementation — Phase 4, behind a feature flag.
///
/// Development Mode is limited to 5 authorized users, so the source
/// is only suitable for development and testers.
final class SpotifyWebAPISource: MusicSource {
    let kind: MusicSourceKind = .spotifyWebAPI

    var isConnected: Bool { get async { false } }

    func nowPlaying() async throws -> PlayRecord? {
        throw AppError.notImplemented(feature: MusicSourceKind.spotifyWebAPI.localizedName)
    }

    func plays(in interval: DateInterval) async throws -> [PlayRecord] {
        throw AppError.notImplemented(feature: MusicSourceKind.spotifyWebAPI.localizedName)
    }
}

/// MusicKit / Apple Music. Implementation — Phase 4.
final class AppleMusicSource: MusicSource {
    let kind: MusicSourceKind = .appleMusic

    var isConnected: Bool { get async { false } }

    func nowPlaying() async throws -> PlayRecord? {
        throw AppError.notImplemented(feature: MusicSourceKind.appleMusic.localizedName)
    }

    func plays(in interval: DateInterval) async throws -> [PlayRecord] {
        throw AppError.notImplemented(feature: MusicSourceKind.appleMusic.localizedName)
    }
}
