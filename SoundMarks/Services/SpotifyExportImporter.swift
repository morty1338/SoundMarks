import Foundation

/// Import of streaming history from Spotify's data export.
///
/// Both exports are understood: Extended Streaming History (`Streaming_History_Audio_*.json`,
/// the whole account lifetime) and the short Account data export
/// (`StreamingHistory_music_*.json`, the last year).
///
/// The Web API isn't involved: the user requests the archive on the account's privacy
/// page, Spotify sends a ZIP with JSON files, the app
/// parses them on the device. The file itself is deleted after parsing.
final class SpotifyExportImporter: StreamingHistoryImporting {
    let kind: MusicSourceKind = .spotifyExport

    private let store: PlayHistoryStore

    init(store: PlayHistoryStore = .shared) {
        self.store = store
    }

    var isConnected: Bool {
        get async { await !store.isEmpty }
    }

    /// The export file is history, it doesn't know "now playing".
    func nowPlaying() async throws -> PlayRecord? { nil }

    func plays(in interval: DateInterval) async throws -> [PlayRecord] {
        await store.plays(in: interval).filter { $0.source == .spotifyExport }
    }

    // MARK: - Import

    func importArchive(at url: URL) async throws -> StreamingHistoryImportSummary {
        // The file comes from Files or the share sheet — access to a security-scoped resource is needed.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let payloads: [Data]
        do {
            payloads = try Self.streamingHistoryPayloads(at: url)
        } catch let error as ZIPArchive.Failure {
            throw AppError.importFileUnreadable(reason: error.errorDescription ?? "zip")
        } catch {
            throw AppError.importFileUnreadable(reason: error.localizedDescription)
        }

        guard !payloads.isEmpty else {
            throw AppError.importFileUnreadable(
                reason: "no Streaming_History_Audio files"
            )
        }

        var records: [PlayRecord] = []
        var skippedShort = 0

        for payload in payloads {
            let entries: [Entry]
            do {
                entries = try Self.decoder.decode([Entry].self, from: payload)
            } catch {
                Log.music.error("History file not parsed: \(error.localizedDescription, privacy: .public)")
                continue
            }

            for entry in entries {
                guard let record = entry.playRecord() else { continue }
                // Tracks shorter than 30 seconds don't count as a memory.
                if record.isMeaningfulPlayback {
                    records.append(record)
                } else {
                    skippedShort += 1
                }
            }
        }

        guard !records.isEmpty else {
            throw AppError.importFileUnreadable(reason: "no playable tracks")
        }

        let summary = try await store.merge(records)
        return StreamingHistoryImportSummary(
            playCount: records.count,
            coveredInterval: summary.coveredInterval,
            skippedShortPlays: skippedShort
        )
    }

    func discardImportedHistory() async throws {
        await store.removeAll()
    }

    // MARK: - Parsing the file

    /// Contents of all music history files: `Streaming_History_Audio_*.json` (Extended)
    /// or `StreamingHistory_music_*.json` (Account data).
    /// Accepts both a ZIP and a single JSON — the user may have unpacked the archive.
    private static func streamingHistoryPayloads(at url: URL) throws -> [Data] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)

        if url.pathExtension.lowercased() == "json" || data.starts(with: [0x5B]) {
            return [data]
        }

        let archive = try ZIPArchive(data: data)
        let wanted = archive.entries.filter { entry in
            guard !entry.isDirectory else { return false }
            let name = (entry.path as NSString).lastPathComponent
            guard name.lowercased().hasSuffix(".json"), !name.hasPrefix(".") else { return false }
            return name.hasPrefix("Streaming_History_Audio")
                || name.hasPrefix("endsong")
                // Account data: `StreamingHistory_music_0.json`, older exports `StreamingHistory0.json`.
                || (name.hasPrefix("StreamingHistory") && !name.lowercased().contains("podcast"))
        }

        return try wanted.map { try archive.contents(of: $0) }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let raw = try container.singleValueContainer().decode(String.self)
            if let date = iso8601WithFraction.date(from: raw) ?? iso8601.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: try container.singleValueContainer(),
                                                   debugDescription: "unexpected ts \(raw)")
        }
        return decoder
    }()

    // ISO8601DateFormatter isn't marked Sendable, but date parsing with it is thread-safe.
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601WithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// `endTime` of the Account data export: "2024-03-01 18:22", in UTC.
    nonisolated(unsafe) private static let accountDataDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// One history entry — from the Extended or the Account data export.
    private struct Entry: Decodable {
        let ts: Date
        let msPlayed: Int?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let trackURI: String?

        /// Extended Streaming History.
        enum CodingKeys: String, CodingKey {
            case ts
            case msPlayed = "ms_played"
            case trackName = "master_metadata_track_name"
            case artistName = "master_metadata_album_artist_name"
            case albumName = "master_metadata_album_album_name"
            case trackURI = "spotify_track_uri"
        }

        /// Account data: no album and no URI. `endTime` is, like `ts`, the moment playback stopped.
        enum AccountDataKeys: String, CodingKey {
            case endTime, msPlayed, trackName, artistName
        }

        init(from decoder: Decoder) throws {
            let extended = try decoder.container(keyedBy: CodingKeys.self)
            if extended.contains(.ts) {
                ts = try extended.decode(Date.self, forKey: .ts)
                msPlayed = try extended.decodeIfPresent(Int.self, forKey: .msPlayed)
                trackName = try extended.decodeIfPresent(String.self, forKey: .trackName)
                artistName = try extended.decodeIfPresent(String.self, forKey: .artistName)
                albumName = try extended.decodeIfPresent(String.self, forKey: .albumName)
                trackURI = try extended.decodeIfPresent(String.self, forKey: .trackURI)
                return
            }

            let short = try decoder.container(keyedBy: AccountDataKeys.self)
            let raw = try short.decode(String.self, forKey: .endTime)
            guard let date = SpotifyExportImporter.accountDataDate.date(from: raw) else {
                throw DecodingError.dataCorruptedError(forKey: .endTime, in: short,
                                                       debugDescription: "unexpected endTime \(raw)")
            }
            ts = date
            msPlayed = try short.decodeIfPresent(Int.self, forKey: .msPlayed)
            trackName = try short.decodeIfPresent(String.self, forKey: .trackName)
            artistName = try short.decodeIfPresent(String.self, forKey: .artistName)
            albumName = nil
            trackURI = nil
        }

        /// `nil` for podcasts and empty entries — they have no track name.
        func playRecord() -> PlayRecord? {
            guard let trackName, !trackName.isEmpty,
                  let artistName, !artistName.isEmpty
            else { return nil }

            return PlayRecord(
                playedAt: ts,
                title: trackName,
                artist: artistName,
                album: albumName,
                playedDuration: msPlayed.map { .milliseconds($0) },
                spotifyURI: trackURI,
                source: .spotifyExport
            )
        }
    }
}
