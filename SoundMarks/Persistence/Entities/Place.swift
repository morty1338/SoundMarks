import CoreData
import CoreLocation
import Foundation

/// A place on the map linked to a track, media and a memory date.
@objc(Place)
final class Place: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    /// Short name from reverse geocoding: a POI or neighborhood, not a full address.
    @NSManaged var placeName: String?
    @NSManaged var city: String?
    @NSManaged var country: String?
    @NSManaged var createdAt: Date?
    /// Moment of the last edit — needed when merging shared maps.
    @NSManaged var updatedAt: Date?
    @NSManaged var eventYear: Int16
    /// 0 — month not specified.
    @NSManaged var eventMonth: Int16
    /// 0 — day not specified.
    @NSManaged var eventDay: Int16
    @NSManaged var note: String?
    /// Pin style override for this place; `nil` — the global setting is used.
    @NSManaged var pinStyleRaw: String?
    /// Record skin (`RecordSkin.id`); `nil` — the default skin from the profile.
    @NSManaged var skinID: String?
    @NSManaged var geofenceEnabled: Bool
    /// Who added the place — their avatar is shown on the pin of a shared map.
    @NSManaged var authorProfileId: UUID?
    /// Deleted but kept as a marker: when merging a shared map the deletion has to reach the friend.
    /// Not `isDeleted` — that name is already taken by `NSManagedObject`.
    @NSManaged var isTombstoned: Bool
    @NSManaged var lastGeofenceNotifiedAt: Date?

    @NSManaged var track: Track?
    @NSManaged var media: Set<MediaItem>?
    @NSManaged var map: MemoryMap?
    @NSManaged var trip: Trip?

    /// `createdAt` and `id` are filled in automatically when the object is created.
    override func awakeFromInsert() {
        super.awakeFromInsert()
        if id == nil { id = UUID() }
        let now = Date()
        if createdAt == nil { createdAt = now }
        if updatedAt == nil { updatedAt = now }
    }

    override func willSave() {
        super.willSave()
        // Set the edit timestamp without triggering another save.
        let now = Date()
        if changedValues()["updatedAt"] == nil, updatedAt.map({ now.timeIntervalSince($0) > 1 }) ?? true {
            setPrimitiveValue(now, forKey: "updatedAt")
        }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<Place> {
        NSFetchRequest<Place>(entityName: "Place")
    }
}

extension Place {
    var coordinate: CLLocationCoordinate2D {
        get { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
        }
    }

    /// Memory date respecting precision. `nil` if the year isn't set.
    var eventDate: EventDate? {
        get { EventDate(storedYear: eventYear, storedMonth: eventMonth, storedDay: eventDay) }
        set {
            eventYear = newValue?.storedYear ?? 0
            eventMonth = newValue?.storedMonth ?? 0
            eventDay = newValue?.storedDay ?? 0
        }
    }

    /// Pin style: the place's override or the given global style.
    func pinStyle(fallback: PinStyle) -> PinStyle {
        pinStyleRaw.flatMap(PinStyle.init(rawValue:)) ?? fallback
    }

    var pinStyleOverride: PinStyle? {
        get { pinStyleRaw.flatMap(PinStyle.init(rawValue:)) }
        set { pinStyleRaw = newValue?.rawValue }
    }

    /// Media in the order set by the user.
    var orderedMedia: [MediaItem] {
        (media ?? []).sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return (lhs.takenAt ?? .distantPast) < (rhs.takenAt ?? .distantPast)
        }
    }

    /// The place's geofence, if monitoring is enabled for it.
    var geofenceRegion: GeofenceRegion? {
        guard geofenceEnabled, let id else { return nil }
        return GeofenceRegion(id: id, latitude: latitude, longitude: longitude)
    }
}

/// Which places to select. Deletion markers (tombstones) never get in.
enum PlaceScope: Equatable, Sendable {
    /// My planet.
    case mine
    /// A specific map: a friend's planet or a shared map.
    case map(UUID)
    /// Several maps at once — all friend planets on the "Friends Marks" screen.
    case maps([UUID])
    /// What can be reminded about: my maps and shared ones, but not snapshots of friends' maps.
    case remindable

    var predicate: NSPredicate {
        let alive = NSPredicate(format: "isTombstoned == NO")
        let scope: NSPredicate = switch self {
        case .mine:
            NSPredicate(format: "map == nil OR map.kindRaw == %@", MemoryMapKind.own.rawValue)
        case .map(let id):
            NSPredicate(format: "map.id == %@", id as CVarArg)
        case .maps(let ids):
            NSPredicate(format: "map.id IN %@", ids)
        case .remindable:
            NSPredicate(format: "map == nil OR map.kindRaw != %@", MemoryMapKind.friend.rawValue)
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [alive, scope])
    }
}

extension Place {
    @nonobjc class func fetchRequest(scope: PlaceScope) -> NSFetchRequest<Place> {
        let request = fetchRequest()
        request.predicate = scope.predicate
        return request
    }

    /// Deletion for sync: the place stays as a marker so the deletion reaches the friend.
    func markDeleted(at date: Date = Date()) {
        isTombstoned = true
        updatedAt = date
        if let context = managedObjectContext {
            track.map(context.delete)
            (media ?? []).forEach(context.delete)
        }
        note = nil
    }
}
