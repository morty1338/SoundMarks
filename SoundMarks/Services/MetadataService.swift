import Foundation

/// Track metadata: artwork and a 30-second preview.
/// Implemented with the iTunes Search API, without authorization, with a local cache.
protocol MetadataService: Sendable {
    /// Free-text search — for picking a track manually.
    func search(query: String, limit: Int) async throws -> [TrackMetadata]

    /// Targeted "artist + track" search — for enriching a history entry.
    func metadata(artist: String, title: String) async throws -> TrackMetadata?
}

extension MetadataService {
    func search(query: String) async throws -> [TrackMetadata] {
        try await search(query: query, limit: 25)
    }
}
