import Foundation

/// Track metadata from the catalog (iTunes Search API): artwork and a 30-second preview.
struct TrackMetadata: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let artworkURL: URL?
    /// A 30-second clip to play in the place card.
    let previewURL: URL?

    init(id: String,
         title: String,
         artist: String,
         album: String? = nil,
         artworkURL: URL? = nil,
         previewURL: URL? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.previewURL = previewURL
    }
}
