import Foundation

/// Last.fm configuration. The key is issued at https://www.last.fm/api/account/create
/// and belongs to the app's developer, not the user.
enum LastFmConfiguration {
    /// The key comes from `Config/Secrets.xcconfig` via Info.plist — it's not in the code or in git.
    /// While it is empty the source honestly reports that it isn't configured, and the app works without Last.fm.
    static let apiKey: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "LastFmAPIKey") as? String ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    static var isConfigured: Bool { !apiKey.isEmpty }
}

/// A source that can top up history into the local store.
protocol HistorySyncing: MusicSource {
    /// Downloads history for an interval and puts it into `PlayHistoryStore`.
    /// - Returns: how many plays were added.
    func syncHistory(in interval: DateInterval,
                     progress: @Sendable @escaping (Double) -> Void) async throws -> Int
}

/// Last.fm `user.getRecentTracks`: history with timestamps and the current track.
///
/// Covers Spotify users via scrobbling and doesn't require waiting for
/// the archive — that is why it is the "quick start" in onboarding.
actor LastFmSource: HistorySyncing {
    nonisolated let kind: MusicSourceKind = .lastFm

    private let session: URLSession
    private let store: PlayHistoryStore

    /// Last.fm asks for no more than five requests per second.
    private let pageDelay = Duration.milliseconds(250)
    private let pageSize = 200
    /// Protection against endless pagination on very large accounts.
    private let maximumPages = 200

    init(session: URLSession = .metadata, store: PlayHistoryStore = .shared) {
        self.session = session
        self.store = store
    }

    var username: String? {
        get { Keychain.string(for: .lastFmUsername) }
    }

    var isConnected: Bool {
        LastFmConfiguration.isConfigured && !(username ?? "").isEmpty
    }

    func connect(username: String) throws {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.other(message: String(localized: "error.lastFm.emptyUsername",
                                                 defaultValue: "Enter your Last.fm username."))
        }
        guard LastFmConfiguration.isConfigured else { throw AppError.lastFmNotConfigured }
        Keychain.set(trimmed, for: .lastFmUsername)
    }

    func disconnect() {
        Keychain.remove(.lastFmUsername)
        Keychain.remove(.lastFmSessionKey)
    }

    // MARK: - MusicSource

    func nowPlaying() async throws -> PlayRecord? {
        let page = try await fetchPage(limit: 1, page: 1, from: nil, to: nil)
        return page.tracks.first { $0.isNowPlaying }?.playRecord(fallbackDate: Date())
    }

    func plays(in interval: DateInterval) async throws -> [PlayRecord] {
        try await fetchAll(in: interval, progress: { _ in })
    }

    // MARK: - HistorySyncing

    func syncHistory(in interval: DateInterval,
                     progress: @Sendable @escaping (Double) -> Void) async throws -> Int {
        let records = try await fetchAll(in: interval, progress: progress)
        guard !records.isEmpty else { return 0 }
        _ = try await store.merge(records)
        return records.count
    }

    // MARK: - Network

    private func fetchAll(in interval: DateInterval,
                          progress: @Sendable @escaping (Double) -> Void) async throws -> [PlayRecord] {
        guard LastFmConfiguration.isConfigured else { throw AppError.lastFmNotConfigured }
        guard let username, !username.isEmpty else {
            throw AppError.musicSourceNotConnected(.lastFm)
        }

        var records: [PlayRecord] = []
        var page = 1
        var totalPages = 1

        repeat {
            try Task.checkCancellation()

            let result = try await fetchPage(limit: pageSize,
                                             page: page,
                                             from: interval.start,
                                             to: interval.end)
            totalPages = min(result.totalPages, maximumPages)

            for track in result.tracks where !track.isNowPlaying {
                guard let record = track.playRecord(fallbackDate: nil) else { continue }
                records.append(record)
            }

            progress(totalPages > 0 ? Double(page) / Double(totalPages) : 1)
            page += 1

            if page <= totalPages { try? await Task.sleep(for: pageDelay) }
        } while page <= totalPages

        return records.sorted { $0.playedAt < $1.playedAt }
    }

    private func fetchPage(limit: Int, page: Int, from: Date?, to: Date?) async throws -> Page {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "ws.audioscrobbler.com"
        components.path = "/2.0/"
        var items = [
            URLQueryItem(name: "method", value: "user.getrecenttracks"),
            URLQueryItem(name: "user", value: username ?? ""),
            URLQueryItem(name: "api_key", value: LastFmConfiguration.apiKey),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        if let from { items.append(URLQueryItem(name: "from", value: String(Int(from.timeIntervalSince1970)))) }
        if let to { items.append(URLQueryItem(name: "to", value: String(Int(to.timeIntervalSince1970)))) }
        components.queryItems = items

        guard let url = components.url else { throw AppError.networkUnavailable }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError {
            Log.music.error("Last.fm unavailable: \(error.code.rawValue, privacy: .public)")
            throw AppError.networkUnavailable
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // 403 — invalid key, 404 — no such user.
            throw http.statusCode == 404
                ? AppError.other(message: String(localized: "error.lastFm.unknownUser",
                                                 defaultValue: "Last.fm doesn’t know that user."))
                : AppError.networkUnavailable
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data).recenttracks.page
        } catch {
            Log.music.error("Could not parse the Last.fm response: \(error.localizedDescription, privacy: .public)")
            throw AppError.other(message: String(localized: "error.lastFm.unreadable",
                                                 defaultValue: "Last.fm returned an unexpected response."))
        }
    }

    // MARK: - Parsing the response

    private struct Page {
        let tracks: [Track]
        let totalPages: Int
    }

    private struct Response: Decodable {
        let recenttracks: RecentTracks

        struct RecentTracks: Decodable {
            let track: [Track]
            let attr: Attr?

            enum CodingKeys: String, CodingKey {
                case track
                case attr = "@attr"
            }

            var page: Page {
                Page(tracks: track, totalPages: Int(attr?.totalPages ?? "1") ?? 1)
            }
        }

        struct Attr: Decodable {
            let totalPages: String?
        }
    }

    private struct Track: Decodable {
        let name: String
        let artist: Text
        let album: Text?
        let date: PlayedAt?
        let attr: Attr?

        enum CodingKeys: String, CodingKey {
            case name, artist, album, date
            case attr = "@attr"
        }

        struct Text: Decodable {
            let value: String

            enum CodingKeys: String, CodingKey { case value = "#text" }
        }

        struct PlayedAt: Decodable {
            let uts: String
        }

        struct Attr: Decodable {
            let nowplaying: String?
        }

        var isNowPlaying: Bool { attr?.nowplaying == "true" }

        func playRecord(fallbackDate: Date?) -> PlayRecord? {
            let playedAt: Date
            if let seconds = date.flatMap({ TimeInterval($0.uts) }) {
                playedAt = Date(timeIntervalSince1970: seconds)
            } else if let fallbackDate {
                playedAt = fallbackDate
            } else {
                return nil
            }

            guard !name.isEmpty, !artist.value.isEmpty else { return nil }
            return PlayRecord(
                playedAt: playedAt,
                title: name,
                artist: artist.value,
                album: album?.value.isEmpty == false ? album?.value : nil,
                // Last.fm doesn't report how long a track played: scrobbles are already filtered by the service.
                playedDuration: nil,
                spotifyURI: nil,
                source: .lastFm
            )
        }
    }
}
