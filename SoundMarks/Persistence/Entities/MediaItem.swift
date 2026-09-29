import CoreData
import Foundation

/// A photo or video attached to a place.
///
/// The personal map stores only the PhotoKit asset `localIdentifier` — the bytes stay in the library.
/// Shared maps need a copy of the data (`assetData`), because participants
/// don't have access to each other's libraries.
@objc(MediaItem)
final class MediaItem: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    /// `MediaKind.rawValue`.
    @NSManaged var typeRaw: String?
    /// `PHAsset.localIdentifier` — for the personal map.
    @NSManaged var localIdentifier: String?
    /// A media copy — for places from friends and shared maps.
    @NSManaged var imageData: Data?
    @NSManaged var takenAt: Date?
    @NSManaged var order: Int16

    @NSManaged var place: Place?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        if id == nil { id = UUID() }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<MediaItem> {
        NSFetchRequest<MediaItem>(entityName: "MediaItem")
    }
}

extension MediaItem {
    var kind: MediaKind {
        get { typeRaw.flatMap(MediaKind.init(rawValue:)) ?? .photo }
        set { typeRaw = newValue.rawValue }
    }
}
