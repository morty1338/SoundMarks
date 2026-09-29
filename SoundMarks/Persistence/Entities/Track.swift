import CoreData
import Foundation

/// Track linked to a place (1:1).
@objc(Track)
final class Track: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var artist: String?
    @NSManaged var album: String?
    @NSManaged var artworkURL: String?
    /// 30-second preview from the iTunes Search API.
    @NSManaged var previewURL: String?
    @NSManaged var spotifyURI: String?
    /// `MusicSourceKind.rawValue` — where the track came into the app from.
    @NSManaged var sourceRaw: String?

    @NSManaged var place: Place?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        if id == nil { id = UUID() }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<Track> {
        NSFetchRequest<Track>(entityName: "Track")
    }
}

extension Track {
    var source: MusicSourceKind {
        get { sourceRaw.flatMap(MusicSourceKind.init(rawValue:)) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var artworkLink: URL? { artworkURL.flatMap(URL.init(string:)) }
    var previewLink: URL? { previewURL.flatMap(URL.init(string:)) }

    /// Applies catalog metadata without touching the source and the Spotify URI.
    func apply(_ metadata: TrackMetadata) {
        title = metadata.title
        artist = metadata.artist
        album = metadata.album
        artworkURL = metadata.artworkURL?.absoluteString
        previewURL = metadata.previewURL?.absoluteString
    }
}
