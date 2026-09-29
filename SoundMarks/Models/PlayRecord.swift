import Foundation

/// One play: what played and when. A shared format for all `MusicSource`s.
struct PlayRecord: Hashable, Sendable, Identifiable, Codable {
    /// Moment of the play (for history — the time the track ended, as Spotify reports in `ts`).
    let playedAt: Date
    let title: String
    let artist: String
    let album: String?
    /// How long the track played. `nil` if the source doesn't report it.
    let playedDuration: Duration?
    let spotifyURI: String?
    let source: MusicSourceKind

    var id: String { "\(source.rawValue)|\(playedAt.timeIntervalSince1970)|\(artist)|\(title)" }

    init(playedAt: Date,
         title: String,
         artist: String,
         album: String? = nil,
         playedDuration: Duration? = nil,
         spotifyURI: String? = nil,
         source: MusicSourceKind) {
        self.playedAt = playedAt
        self.title = title
        self.artist = artist
        self.album = album
        self.playedDuration = playedDuration
        self.spotifyURI = spotifyURI
        self.source = source
    }

    /// Threshold below which a play counts as "skipped" and takes no part in matching.
    static let minimumMeaningfulPlayback = Duration.seconds(30)

    /// Whether the track played long enough to count as a memory.
    /// If the source doesn't report the duration — count it as significant.
    var isMeaningfulPlayback: Bool {
        guard let playedDuration else { return true }
        return playedDuration >= Self.minimumMeaningfulPlayback
    }

    /// Key for joining identical tracks from different sources.
    var trackKey: String { "\(artist.lowercased())|\(title.lowercased())" }
}
