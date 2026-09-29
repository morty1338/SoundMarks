import Foundation

/// A source of information about listened music.
///
/// Implementations: Spotify history file import, Last.fm, Spotify Web API (behind a feature flag),
/// Apple Music. The app doesn't depend on any single source — see the limits
/// of the Spotify Web API in Development Mode.
protocol MusicSource: Sendable {
    var kind: MusicSourceKind { get }

    /// Whether the source is connected: there is a token, a username or imported history.
    var isConnected: Bool { get async }

    /// What is playing now. `nil` — nothing is playing.
    /// - Throws: `AppError.musicSourceNotConnected` if the source isn't configured.
    func nowPlaying() async throws -> PlayRecord?

    /// Listening history for an interval, in ascending time order.
    func plays(in interval: DateInterval) async throws -> [PlayRecord]
}

/// A source filled from an export file rather than the network.
protocol StreamingHistoryImporting: MusicSource {
    /// Parses an Extended Streaming History archive and stores the plays locally.
    ///
    /// The file itself is deleted after processing — only the places confirmed
    /// by the user remain on the device.
    func importArchive(at url: URL) async throws -> StreamingHistoryImportSummary

    /// Deletes imported history.
    func discardImportedHistory() async throws
}

/// Result of importing listening history.
struct StreamingHistoryImportSummary: Hashable, Sendable {
    let playCount: Int
    /// The period covered by the imported history.
    let coveredInterval: DateInterval?
    /// How many entries were dropped as too short (`ms_played` < 30 s).
    let skippedShortPlays: Int
}
