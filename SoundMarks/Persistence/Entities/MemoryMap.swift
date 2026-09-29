import CoreData
import Foundation

/// Map kind.
enum MemoryMapKind: String, Sendable, CaseIterable {
    /// My personal map.
    case own
    /// Snapshot of a friend's map — view only.
    case friend
    /// A shared map run by two people.
    case shared
}

/// A map: personal, a snapshot of a friend's map, or shared.
///
/// The entity is called `MemoryMap`, not `Map`, to avoid clashing with `SwiftUI.Map`.
@objc(MemoryMap)
final class MemoryMap: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    /// `MemoryMapKind.rawValue`.
    @NSManaged var kindRaw: String?
    /// The owner's display name — for the author avatar on a shared map pin.
    @NSManaged var ownerName: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    /// Whose map this is: my profile, a friend, or the creator of a shared map.
    @NSManaged var ownerProfileId: UUID?
    /// Shared map participants — profile UUIDs separated by commas.
    @NSManaged var participantIDsRaw: String?
    /// When the map last exchanged data with a friend.
    @NSManaged var lastSyncedAt: Date?
    /// A friend's planet was added to my screen (the "Add Planet" button).
    @NSManaged var isAdded: Bool
    /// My caption for someone else's or a shared planet. My own planet is captioned via `name`.
    @NSManaged var title: String?
    /// Order on the home screen — the planet can swap places with neighbors.
    @NSManaged var sortOrder: Int32

    @NSManaged var places: Set<Place>?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        if id == nil { id = UUID() }
        if createdAt == nil { createdAt = Date() }
        if kindRaw == nil { kindRaw = MemoryMapKind.own.rawValue }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<MemoryMap> {
        NSFetchRequest<MemoryMap>(entityName: "MemoryMap")
    }
}

extension MemoryMap {
    var participantIDs: [UUID] {
        get { (participantIDsRaw ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
        set { participantIDsRaw = newValue.map(\.uuidString).joined(separator: ",") }
    }

    /// The map's live places — without deletion markers.
    var livePlaces: [Place] { (places ?? []).filter { !$0.isTombstoned } }

    var kind: MemoryMapKind {
        get { kindRaw.flatMap(MemoryMapKind.init(rawValue:)) ?? .own }
        set { kindRaw = newValue.rawValue }
    }
}
