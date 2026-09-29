import CoreData
import Foundation

/// Friendship state.
enum FriendshipStatus: String, Sendable, CaseIterable {
    /// Friends: both sides confirmed.
    case friend
    /// I received a request — waiting for my decision.
    case incoming
    /// I sent a request — waiting for the friend's confirmation.
    case outgoing
}

/// A profile: mine or a friend's.
///
/// Links to maps and places are by identifier, not Core Data relationships:
/// that way map snapshots move between devices without rewriting the object graph.
@objc(Profile)
final class Profile: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var nickname: String?
    @NSManaged var avatarData: Data?
    /// Color of the initials circle when there's no photo.
    @NSManaged var avatarColorHex: String?
    /// 8 characters, generated on the device and never changes.
    @NSManaged var uniqueCode: String?
    @NSManaged var isMe: Bool
    @NSManaged var isBlocked: Bool
    /// Only for my profile: whether friends see my planet.
    @NSManaged var planetVisible: Bool
    @NSManaged var statusRaw: String?
    @NSManaged var lastSyncedAt: Date?
    @NSManaged var createdAt: Date?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        if id == nil { id = UUID() }
        if createdAt == nil { createdAt = Date() }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<Profile> {
        NSFetchRequest<Profile>(entityName: "Profile")
    }
}

extension Profile {
    var status: FriendshipStatus {
        get { statusRaw.flatMap(FriendshipStatus.init(rawValue:)) ?? .friend }
        set { statusRaw = newValue.rawValue }
    }

    var initials: String {
        let parts = (nickname ?? "").split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
