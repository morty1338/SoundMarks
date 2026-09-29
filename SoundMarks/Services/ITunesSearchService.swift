import Foundation

/// Track metadata from the iTunes Search API: artwork and a 30-second preview.
/// No authorization needed; responses are cached on disk and in memory.
actor ITunesSearchService: MetadataService {
    private let session: URLSession
    private let storefront: String
    private var memoryCache: [CacheKey: [TrackMetadata]] = [:]

    private struct CacheKey: Hashable {
        let term: String
        let limit: Int
    }

    init(session: URLSession = .metadata, storefront: String? = nil) {
        self.session = session
        self.storefront = storefront ?? Locale.current.region?.identifier ?? "US"
    }

    // MARK: - MetadataService

    func search(query: String, limit: Int) async throws -> [TrackMetadata] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return [] }

        let key = CacheKey(term: term.lowercased(), limit: limit)
        if let cached = memoryCache[key] { return cached }

        let results = try await fetch(term: term, limit: limit)
        memoryCache[key] = results
        return results
    }

    func metadata(artist: String, title: String) async throws -> TrackMetadata? {
        let results = try await search(query: "\(artist) \(title)", limit: 10)
        // An exact match by artist and title, otherwise the first result.
        return results.first { $0.matches(artist: artist, title: title) } ?? results.first
    }

    // MARK: - Network

    private func fetch(term: String, limit: Int) async throws -> [TrackMetadata] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200))),
            URLQueryItem(name: "country", value: storefront),
        ]

        guard let url = components.url else {
            throw AppError.other(message: String(localized: "error.badSearchQuery",
                                                 defaultValue: "Invalid search query."))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError {
            Log.metadata.error("iTunes Search unavailable: \(error.code.rawValue, privacy: .public)")
            throw AppError.networkUnavailable
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            Log.metadata.error("iTunes Search returned \(http.statusCode, privacy: .public)")
            // 403 here means the rate limit was exceeded.
            throw http.statusCode == 403
                ? AppError.other(message: String(localized: "error.searchRateLimited",
                                                 defaultValue: "Too many catalog requests. Try again in a minute."))
                : AppError.networkUnavailable
        }

        do {
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            return decoded.results.compactMap(TrackMetadata.init(item:))
        } catch {
            Log.metadata.error("Could not parse the iTunes Search response: \(error.localizedDescription, privacy: .public)")
            throw AppError.other(message: String(localized: "error.searchUnreadable",
                                                 defaultValue: "The catalog returned an unexpected response."))
        }
    }

    fileprivate struct SearchResponse: Decodable {
        let results: [Item]

        struct Item: Decodable {
            let trackId: Int?
            let trackName: String?
            let artistName: String?
            let collectionName: String?
            let artworkUrl100: String?
            let previewUrl: String?
        }
    }
}

private extension TrackMetadata {
    init?(item: ITunesSearchService.SearchResponse.Item) {
        guard let title = item.trackName, let artist = item.artistName else { return nil }
        self.init(
            id: item.trackId.map(String.init) ?? "\(artist)|\(title)",
            title: title,
            artist: artist,
            album: item.collectionName,
            artworkURL: item.artworkUrl100.flatMap { URL(string: Self.upscaled($0)) },
            previewURL: item.previewUrl.flatMap(URL.init(string:))
        )
    }

    /// iTunes returns 100×100 artwork; the same path with another size gives a larger version.
    static func upscaled(_ artworkURL: String) -> String {
        artworkURL.replacingOccurrences(of: "/100x100bb", with: "/600x600bb")
    }
}

extension TrackMetadata {
    func matches(artist otherArtist: String, title otherTitle: String) -> Bool {
        artist.caseInsensitiveCompare(otherArtist) == .orderedSame
            && title.caseInsensitiveCompare(otherTitle) == .orderedSame
    }
}

extension URLSession {
    /// Session for the catalog: a disk cache so the network isn't hit on every card display.
    static let metadata: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(memoryCapacity: 8 << 20,
                                          diskCapacity: 64 << 20,
                                          directory: nil)
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
}
