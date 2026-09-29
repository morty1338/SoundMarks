import CoreData
import Foundation
import Observation

/// Profiles: mine and friends'. Everything is stored only on the device.
@MainActor
@Observable
final class ProfileStore {
    private(set) var me: Profile?
    private(set) var friends: [Profile] = []
    private(set) var incomingRequests: [Profile] = []

    @ObservationIgnored private let persistence: PersistenceController

    init(persistence: PersistenceController) {
        self.persistence = persistence
        reload()
    }

    private var context: NSManagedObjectContext { persistence.viewContext }

    func reload() {
        let meRequest = Profile.fetchRequest()
        meRequest.predicate = NSPredicate(format: "isMe == YES")
        meRequest.fetchLimit = 1
        me = try? context.fetch(meRequest).first

        let others = Profile.fetchRequest()
        others.predicate = NSPredicate(format: "isMe == NO AND isBlocked == NO")
        others.sortDescriptors = [NSSortDescriptor(key: "nickname", ascending: true)]
        let all = (try? context.fetch(others)) ?? []
        friends = all.filter { $0.status == .friend }
        incomingRequests = all.filter { $0.status == .incoming }
    }

    // MARK: - My profile

    /// The profile is created when the friends screen is opened for the first time.
    @discardableResult
    func createMe(nickname: String, avatarColorHex: String, avatarData: Data?) throws -> Profile {
        if let me { return me }
        let profile = Profile(context: context)
        profile.isMe = true
        profile.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.avatarColorHex = avatarColorHex
        profile.avatarData = avatarData
        profile.uniqueCode = FriendCode.generate()
        // Only confirmed friends see the planet; it can be hidden in settings.
        profile.planetVisible = true
        try persistence.save()
        reload()
        return profile
    }

    func updateMe(nickname: String? = nil, avatarColorHex: String? = nil,
                  avatarData: Data?? = nil, planetVisible: Bool? = nil) throws {
        guard let me else { return }
        if let nickname { me.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let avatarColorHex { me.avatarColorHex = avatarColorHex }
        if let avatarData { me.avatarData = avatarData }
        if let planetVisible { me.planetVisible = planetVisible }
        try persistence.save()
        reload()
    }

    // MARK: - Friends

    func profile(id: UUID) -> Profile? {
        let request = Profile.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func profile(code: String) -> Profile? {
        let request = Profile.fetchRequest()
        request.predicate = NSPredicate(format: "uniqueCode ==[c] %@", FriendCode.normalized(code))
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// A friend we can accept data from: confirmed and not blocked.
    func trustedFriend(id: UUID) -> Profile? {
        guard let profile = profile(id: id), !profile.isMe, !profile.isBlocked,
              profile.status == .friend else { return nil }
        return profile
    }

    /// Creates or updates a profile from data from another device.
    @discardableResult
    func upsert(_ dto: ProfileDTO, status: FriendshipStatus? = nil) throws -> Profile {
        let profile = profile(id: dto.id) ?? Profile(context: context)
        profile.id = dto.id
        profile.nickname = dto.nickname
        profile.uniqueCode = dto.uniqueCode
        profile.avatarColorHex = dto.avatarColorHex
        profile.planetVisible = dto.planetVisible
        if let status { profile.status = status }
        try persistence.save()
        reload()
        return profile
    }

    func accept(_ profile: Profile) throws {
        profile.status = .friend
        try persistence.save()
        reload()
    }

    func decline(_ profile: Profile) throws {
        context.delete(profile)
        try persistence.save()
        reload()
    }

    /// Removes a friend together with the snapshot of their planet.
    func remove(_ profile: Profile) throws {
        if let id = profile.id { deleteFriendPlanet(ownerID: id) }
        context.delete(profile)
        try persistence.save()
        reload()
    }

    /// Blocking: the profile stays so their files and requests are rejected.
    func block(_ profile: Profile) throws {
        profile.isBlocked = true
        if let id = profile.id { deleteFriendPlanet(ownerID: id) }
        try persistence.save()
        reload()
    }

    func markSynced(_ profile: Profile, at date: Date = Date()) {
        profile.lastSyncedAt = date
        try? persistence.save()
        reload()
    }

    func deleteFriendPlanet(ownerID: UUID) {
        let request = MemoryMap.fetchRequest()
        request.predicate = NSPredicate(format: "kindRaw == %@ AND ownerProfileId == %@",
                                        MemoryMapKind.friend.rawValue, ownerID as CVarArg)
        for map in (try? context.fetch(request)) ?? [] {
            context.delete(map)
        }
    }

    func dto(for profile: Profile) -> ProfileDTO? {
        guard let id = profile.id, let code = profile.uniqueCode else { return nil }
        return ProfileDTO(id: id,
                          nickname: profile.nickname ?? "",
                          uniqueCode: code,
                          avatarColorHex: profile.avatarColorHex,
                          avatarFile: nil,
                          planetVisible: profile.planetVisible)
    }
}

/// Unique profile code: 8 characters without look-alikes (0/O, 1/I/L).
enum FriendCode {
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static let length = 8

    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator) ?? "A" })
    }

    /// Case and spaces do not matter — the code is typed by hand.
    static func normalized(_ code: String) -> String {
        code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    }

    static func isValid(_ code: String) -> Bool {
        let value = normalized(code)
        return value.count == length && value.allSatisfy(alphabet.contains)
    }

    /// QR contents: the app scheme plus the code.
    static func qrPayload(for code: String) -> String { "soundmap:\(code)" }

    static func code(fromQR payload: String) -> String? {
        let raw = payload.hasPrefix("soundmap:") ? String(payload.dropFirst("soundmap:".count)) : payload
        return isValid(raw) ? normalized(raw) : nil
    }
}
