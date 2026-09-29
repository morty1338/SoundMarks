import Foundation

/// Stub until the iTunes Search API is implemented in Phase 1.
final class UnavailableMetadataService: MetadataService {
    func search(query: String, limit: Int) async throws -> [TrackMetadata] {
        throw AppError.notImplemented(feature: String(localized: "feature.trackSearch", defaultValue: "Track search"))
    }

    func metadata(artist: String, title: String) async throws -> TrackMetadata? {
        throw AppError.notImplemented(feature: String(localized: "feature.trackSearch", defaultValue: "Track search"))
    }
}
