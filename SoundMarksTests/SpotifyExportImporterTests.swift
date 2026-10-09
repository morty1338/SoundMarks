import Foundation
import Testing

@testable import SoundMarks

/// Parsing Extended Streaming History: Spotify fields, filtering short
/// plays, podcasts, ZIP and "bare" JSON.
@Suite("SpotifyExportImporter")
struct SpotifyExportImporterTests {
    private func entry(ts: String,
                       msPlayed: Int,
                       track: String? = "Instant Crush",
                       artist: String? = "Daft Punk",
                       album: String? = "Random Access Memories") -> [String: Any] {
        var json: [String: Any] = ["ts": ts, "ms_played": msPlayed]
        json["master_metadata_track_name"] = track ?? NSNull()
        json["master_metadata_album_artist_name"] = artist ?? NSNull()
        json["master_metadata_album_album_name"] = album ?? NSNull()
        json["spotify_track_uri"] = "spotify:track:2cGxRwrMyEAp8dEbuZaVv6"
        return json
    }

    private func payload(_ entries: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: entries)
    }

    private func temporaryFile(named name: String, contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name)")
        try contents.write(to: url)
        return url
    }

    /// Each test gets its own store so they don't interfere with each other.
    private func makeImporter() -> (SpotifyExportImporter, PlayHistoryStore) {
        let store = PlayHistoryStore(fileName: "test-history-\(UUID().uuidString).json")
        return (SpotifyExportImporter(store: store), store)
    }

    @Test("A single JSON is parsed")
    func importsPlainJSON() async throws {
        let (importer, store) = makeImporter()
        defer { Task { await store.removeAll() } }

        let data = try payload([
            entry(ts: "2023-08-14T18:32:11Z", msPlayed: 213_000),
            entry(ts: "2023-08-14T18:36:44Z", msPlayed: 180_000, track: "Get Lucky"),
        ])
        let url = try temporaryFile(named: "Streaming_History_Audio_2023.json", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try await importer.importArchive(at: url)
        #expect(summary.playCount == 2)
        #expect(summary.skippedShortPlays == 0)

        let stored = await store.summary()
        #expect(stored.playCount == 2)
        #expect(stored.sources == [.spotifyExport])
    }

    @Test("A ZIP with history files is parsed")
    func importsZIP() async throws {
        let (importer, store) = makeImporter()
        defer { Task { await store.removeAll() } }

        let data = try payload([entry(ts: "2019-03-02T09:00:00Z", msPlayed: 200_000)])
        let zip = ZIPBuilder()
            .adding(name: "Spotify Extended Streaming History/Streaming_History_Audio_2019_0.json",
                    contents: data, compressed: true)
            .adding(name: "Spotify Extended Streaming History/ReadMeFirst.pdf",
                    contents: Data("not json".utf8), compressed: false)
            .build()
        let url = try temporaryFile(named: "export.zip", contents: zip)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try await importer.importArchive(at: url)
        #expect(summary.playCount == 1)
    }

    @Test("A JSON from the Account data export is parsed")
    func importsAccountDataJSON() async throws {
        let (importer, store) = makeImporter()
        defer { Task { await store.removeAll() } }

        let data = try payload([
            ["endTime": "2024-03-01 18:22", "artistName": "Daft Punk",
             "trackName": "Instant Crush", "msPlayed": 213_000],
            ["endTime": "2024-03-01 18:25", "artistName": "Daft Punk",
             "trackName": "Get Lucky", "msPlayed": 5_000],
        ])
        let url = try temporaryFile(named: "StreamingHistory_music_0.json", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try await importer.importArchive(at: url)
        #expect(summary.playCount == 1)
        #expect(summary.skippedShortPlays == 1)

        let year = DateInterval(start: Date(timeIntervalSince1970: 1_704_067_200), duration: 366 * 86_400)
        let record = try #require(await importer.plays(in: year).first)
        #expect(record.title == "Instant Crush")
        #expect(record.artist == "Daft Punk")
        #expect(record.playedAt == Date(timeIntervalSince1970: 1_709_317_320))
        #expect(record.album == nil)
    }

    @Test("A ZIP from the Account data export is parsed, podcasts are skipped")
    func importsAccountDataZIP() async throws {
        let (importer, store) = makeImporter()
        defer { Task { await store.removeAll() } }

        let music = try payload([["endTime": "2024-03-01 18:22", "artistName": "Daft Punk",
                                  "trackName": "Instant Crush", "msPlayed": 213_000]])
        let podcast = try payload([["endTime": "2024-03-02 08:00", "podcastName": "Show",
                                    "episodeName": "Episode", "msPlayed": 900_000]])
        let zip = ZIPBuilder()
            .adding(name: "Spotify Account Data/StreamingHistory_music_0.json",
                    contents: music, compressed: true)
            .adding(name: "Spotify Account Data/StreamingHistory_podcast_0.json",
                    contents: podcast, compressed: true)
            .adding(name: "Spotify Account Data/Userdata.json",
                    contents: Data(#"{"username":"x"}"#.utf8), compressed: false)
            .build()
        let url = try temporaryFile(named: "my_spotify_data.zip", contents: zip)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try await importer.importArchive(at: url)
        #expect(summary.playCount == 1)
    }

    @Test("Plays shorter than 30 seconds are not imported")
    func skipsShortPlays() async throws {
        let (importer, store) = makeImporter()
        defer { Task { await store.removeAll() } }

        let data = try payload([
            entry(ts: "2023-08-14T18:32:11Z", msPlayed: 12_000),
            entry(ts: "2023-08-14T19:32:11Z", msPlayed: 29_999, track: "Skipped"),
            entry(ts: "2023-08-14T20:32:11Z", msPlayed: 30_000, track: "Kept"),
        ])
        let url = try temporaryFile(named: "Streaming_History_Audio.json", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try await importer.importArchive(at: url)
        #expect(summary.playCount == 1)
        #expect(summary.skippedShortPlays == 2)
    }

    @Test("Podcasts and empty entries are skipped")
    func skipsPodcasts() async throws {
        let (importer, store) = makeImporter()
        defer { Task { await store.removeAll() } }

        let data = try payload([
            entry(ts: "2023-08-14T18:32:11Z", msPlayed: 900_000, track: nil, artist: nil),
            entry(ts: "2023-08-14T19:32:11Z", msPlayed: 200_000, track: "Song"),
        ])
        let url = try temporaryFile(named: "Streaming_History_Audio.json", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await importer.importArchive(at: url).playCount == 1)
    }

    @Test("Spotify fields map into PlayRecord")
    func mapsFields() async throws {
        let (importer, store) = makeImporter()
        defer { Task { await store.removeAll() } }

        let data = try payload([entry(ts: "2023-08-14T18:32:11Z", msPlayed: 213_000)])
        let url = try temporaryFile(named: "Streaming_History_Audio.json", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await importer.importArchive(at: url)

        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), end: Date())
        let record = try #require(await store.plays(in: interval).first)
        #expect(record.title == "Instant Crush")
        #expect(record.artist == "Daft Punk")
        #expect(record.album == "Random Access Memories")
        #expect(record.spotifyURI == "spotify:track:2cGxRwrMyEAp8dEbuZaVv6")
        #expect(record.source == .spotifyExport)
        #expect(record.playedDuration == .milliseconds(213_000))
    }

    @Test("Importing the same file again does not double the history")
    func importIsIdempotent() async throws {
        let (importer, store) = makeImporter()
        defer { Task { await store.removeAll() } }

        let data = try payload([entry(ts: "2023-08-14T18:32:11Z", msPlayed: 213_000)])
        let url = try temporaryFile(named: "Streaming_History_Audio.json", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await importer.importArchive(at: url)
        _ = try await importer.importArchive(at: url)
        #expect(await store.summary().playCount == 1)
    }

    @Test("A file without track entries gives a clear error")
    func emptyFileFails() async throws {
        let (importer, store) = makeImporter()
        defer { Task { await store.removeAll() } }

        let url = try temporaryFile(named: "Streaming_History_Audio.json",
                                    contents: try payload([]))
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: AppError.self) {
            _ = try await importer.importArchive(at: url)
        }
    }

    @Test("Deleting history clears the store")
    func discardClearsHistory() async throws {
        let (importer, store) = makeImporter()

        let data = try payload([entry(ts: "2023-08-14T18:32:11Z", msPlayed: 213_000)])
        let url = try temporaryFile(named: "Streaming_History_Audio.json", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await importer.importArchive(at: url)
        #expect(await importer.isConnected)

        try await importer.discardImportedHistory()
        #expect(await store.summary().playCount == 0)
        #expect(await importer.isConnected == false)
    }

    @Test("History is returned by interval and by year")
    func queriesByIntervalAndYear() async throws {
        let (importer, store) = makeImporter()
        defer { Task { await store.removeAll() } }

        let data = try payload([
            entry(ts: "2019-05-01T10:00:00Z", msPlayed: 200_000),
            entry(ts: "2023-08-14T18:32:11Z", msPlayed: 200_000, track: "Later"),
        ])
        let url = try temporaryFile(named: "Streaming_History_Audio.json", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await importer.importArchive(at: url)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let year2019 = try #require(MemoryScanner.interval(for: 2019, calendar: calendar))

        #expect(await store.plays(in: year2019).count == 1)
        #expect(await store.yearsWithPlays(calendar: calendar) == [2023, 2019])
    }
}
