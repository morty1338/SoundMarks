import CoreData
import Foundation
import Observation

/// A specific planet: mine, a friend's or paired (a shared map).
enum PlanetPage: Hashable, Sendable {
    case own(UUID)
    /// Snapshot of a friend's planet — view only.
    case friend(UUID)
    /// Paired planet: both add places.
    case shared(UUID)

    var mapID: UUID {
        switch self {
        case .own(let id), .friend(let id), .shared(let id): id
        }
    }

    var scope: PlaceScope { .map(mapID) }

    var isReadOnly: Bool {
        if case .friend = self { return true }
        return false
    }

    /// Where new places are saved: my planet or a paired one.
    var targetMapID: UUID? { isReadOnly ? nil : mapID }
}

/// Everything needed to show a planet: caption, owner, dots, counter.
struct PlanetInfo: Identifiable, Equatable {
    let page: PlanetPage
    /// Caption below or above the planet.
    var title: String
    /// Owner of a friend's planet or the other participant of a paired one.
    var nickname: String?
    var avatarColorHex: String?
    var avatarData: Data?
    var updatedAt: Date?
    var placeCount: Int
    var dots: [SphereMapping.Coordinate]

    var id: PlanetPage { page }
}

/// All planets of one friend — in the "Friends Marks" grid they lie in a stack.
struct FriendStack: Identifiable, Equatable {
    let ownerID: UUID
    var nickname: String
    var avatarColorHex: String?
    var avatarData: Data?
    var planets: [PlanetInfo]

    var id: UUID { ownerID }
    var placeCount: Int { planets.map(\.placeCount).reduce(0, +) }
}

/// Registry of home screen planets.
///
/// On the left — paired planets, in the center — mine (there may be several, with captions),
/// on the right — the "Friends Marks" grid with friend planets I added via "Add Planet".
@MainActor
@Observable
final class PlanetDirectory {
    private(set) var ownPlanets: [PlanetInfo] = []
    private(set) var sharedPlanets: [PlanetInfo] = []
    /// Friend planets added to the screen, stacked by owner.
    private(set) var friendStacks: [FriendStack] = []
    /// Friend planets that can be added.
    private(set) var availableStacks: [FriendStack] = []

    /// All planets by page — `info(for:)` is called every frame of the planet screen.
    private var infoByPage: [PlanetPage: PlanetInfo] = [:]

    @ObservationIgnored private let persistence: PersistenceController
    @ObservationIgnored private let profiles: ProfileStore
    @ObservationIgnored private var changes: StoreChanges?
    /// Place coordinates per map, read with one query per reload.
    @ObservationIgnored private var coordinates: [NSManagedObjectID: [SphereMapping.Coordinate]] = [:]

    init(persistence: PersistenceController, profiles: ProfileStore) {
        self.persistence = persistence
        self.profiles = profiles
        persistence.adoptOrphanPlaces()
        reload()
        // Route points, tracks and media don't change planets — we don't reload on their saves.
        changes = StoreChanges(entities: ["Place", "MemoryMap", "Profile"]) { [weak self] in
            self?.reload()
        }
    }

    private var context: NSManagedObjectContext { persistence.viewContext }

    /// The main planet — the screen starts with it.
    var mainPlanet: PlanetPage { .own(mainPlanetID) }

    /// The main one is the first created; its order on screen can be anything.
    private(set) var mainPlanetID = UUID()

    /// Sum of records of all added friend planets.
    var friendsPlaceCount: Int { friendStacks.map(\.placeCount).reduce(0, +) }

    /// All added friend planets in a row — for the roulette on the "Friends Marks" screen.
    var friendMapIDs: [UUID] { friendStacks.flatMap { $0.planets.map(\.page.mapID) } }

    func info(for page: PlanetPage) -> PlanetInfo? {
        infoByPage[page]
    }

    // MARK: - Loading

    func reload() {
        // Coordinates of all places — with one dictionary query, without place objects in memory.
        coordinates = (try? PlaceQueries.coordinatesByMap(in: context)) ?? [:]
        let byCreation = (try? persistence.ownPlanets()) ?? []
        let mainID = byCreation.first?.id
        if let mainID, mainID != mainPlanetID { mainPlanetID = mainID }
        // The on-screen order is set by the user; the main planet is simply the first created.
        let own = byCreation.sorted { ($0.sortOrder, $0.createdAt ?? .distantPast)
            < ($1.sortOrder, $1.createdAt ?? .distantPast) }
        let updatedOwn = own.compactMap { map -> PlanetInfo? in
            guard let id = map.id else { return nil }
            return makeInfo(map, page: .own(id),
                            title: map.title ?? (id == mainID
                                ? String(localized: "planet.main", defaultValue: "Main planet")
                                : map.name ?? ""))
        }

        let request = MemoryMap.fetchRequest()
        request.predicate = NSPredicate(format: "kindRaw IN %@",
                                        [MemoryMapKind.friend.rawValue, MemoryMapKind.shared.rawValue])
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true),
                                   NSSortDescriptor(key: "createdAt", ascending: true)]
        let maps = (try? context.fetch(request)) ?? []
        let myID = profiles.me?.id

        var shared: [PlanetInfo] = []
        var added: [UUID: FriendStack] = [:]
        var available: [UUID: FriendStack] = [:]
        var order: [UUID] = []

        for map in maps {
            guard let mapID = map.id else { continue }
            switch map.kind {
            case .friend:
                // Only friends whose planet is visible and who aren't blocked.
                guard let ownerID = map.ownerProfileId,
                      let owner = profiles.trustedFriend(id: ownerID), owner.planetVisible
                else { continue }
                let nickname = owner.nickname ?? map.ownerName ?? ""
                let name = map.title ?? map.name.flatMap { $0.isEmpty ? nil : $0 }
                    ?? String(localized: "planet.friendsPlanet", defaultValue: "\(nickname)'s Planet")
                var info = makeInfo(map, page: .friend(mapID), title: name)
                info.nickname = nickname
                info.avatarColorHex = owner.avatarColorHex
                info.avatarData = owner.avatarData

                if !order.contains(ownerID) { order.append(ownerID) }
                let empty = FriendStack(ownerID: ownerID, nickname: nickname,
                                        avatarColorHex: owner.avatarColorHex,
                                        avatarData: owner.avatarData, planets: [])
                if map.isAdded {
                    added[ownerID, default: empty].planets.append(info)
                } else {
                    available[ownerID, default: empty].planets.append(info)
                }

            case .shared:
                let other = map.participantIDs.first { $0 != myID }.flatMap(profiles.profile(id:))
                if other?.isBlocked == true { continue }
                let nickname = other?.nickname ?? map.name ?? ""
                var info = makeInfo(map, page: .shared(mapID),
                                    title: map.title
                                        ?? String(localized: "planet.pairedCaption",
                                                  defaultValue: "\(nickname) with your Marks"))
                info.nickname = nickname
                info.avatarColorHex = other?.avatarColorHex
                info.avatarData = other?.avatarData
                shared.append(info)

            case .own:
                continue
            }
        }

        let stacks = order.compactMap { added[$0] }
        let availableStacks = order.compactMap { available[$0] }
        if updatedOwn != ownPlanets { ownPlanets = updatedOwn }
        if shared != sharedPlanets { sharedPlanets = shared }
        if stacks != friendStacks { friendStacks = stacks }
        if availableStacks != self.availableStacks { self.availableStacks = availableStacks }

        var byPage: [PlanetPage: PlanetInfo] = [:]
        for info in updatedOwn + shared + stacks.flatMap(\.planets) where byPage[info.page] == nil {
            byPage[info.page] = info
        }
        if byPage != infoByPage { infoByPage = byPage }
    }

    private func makeInfo(_ map: MemoryMap, page: PlanetPage, title: String) -> PlanetInfo {
        let dots = coordinates[map.objectID] ?? []
        return PlanetInfo(page: page, title: title, nickname: nil, avatarColorHex: nil, avatarData: nil,
                          updatedAt: map.lastSyncedAt, placeCount: dots.count, dots: dots)
    }

    // MARK: - Actions

    /// A new own planet with a caption, for example "Italy 2025".
    @discardableResult
    func createOwnPlanet(named name: String) throws -> PlanetPage {
        let map = MemoryMap(context: context)
        map.kind = .own
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        map.name = trimmed
        map.title = trimmed.isEmpty ? nil : trimmed
        map.updatedAt = Date()
        try commit()
        guard let id = map.id else { throw SyncService.Failure.mapNotFound }
        return .own(id)
    }

    /// Planet caption. Empty — revert to the default caption.
    func rename(_ page: PlanetPage, to title: String) throws {
        guard let map = map(id: page.mapID) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        map.title = trimmed.isEmpty ? nil : trimmed
        if case .own = page, !trimmed.isEmpty { map.name = trimmed }
        map.updatedAt = Date()
        try commit()
    }

    // MARK: - Order

    /// Swaps a planet with its neighbor in its row (mine or paired). `step` — −1 or +1.
    @discardableResult
    func move(_ page: PlanetPage, by step: Int) -> Bool {
        let row: [PlanetPage]
        switch page {
        case .own: row = ownPlanets.map(\.page)
        case .shared: row = sharedPlanets.map(\.page)
        case .friend: return false
        }
        guard let index = row.firstIndex(of: page), row.indices.contains(index + step) else { return false }
        var reordered = row
        reordered.swapAt(index, index + step)
        applyOrder(reordered.map(\.mapID))
        return true
    }

    /// Moves a friend's stack in the "Friends Marks" grid.
    func moveStack(ownerID: UUID, to newIndex: Int) {
        var stacks = friendStacks
        guard let index = stacks.firstIndex(where: { $0.ownerID == ownerID }),
              stacks.indices.contains(newIndex), index != newIndex else { return }
        let stack = stacks.remove(at: index)
        stacks.insert(stack, at: newIndex)
        applyOrder(stacks.flatMap { $0.planets.map(\.page.mapID) })
    }

    private func applyOrder(_ ids: [UUID]) {
        for (index, id) in ids.enumerated() {
            map(id: id)?.sortOrder = Int32(index)
        }
        try? commit()
    }

    /// A paired planet is deleted on my side together with its places.
    func deleteShared(_ page: PlanetPage) throws {
        guard case .shared = page, let map = map(id: page.mapID) else { return }
        context.delete(map)
        try commit()
    }

    /// Removes all of a friend's planets from the screen; the snapshots stay in "Add Planet".
    func removeStackFromScreen(ownerID: UUID) throws {
        guard let stack = friendStacks.first(where: { $0.ownerID == ownerID }) else { return }
        for planet in stack.planets {
            map(id: planet.page.mapID)?.isAdded = false
        }
        try commit()
    }

    /// Whether a planet can be removed from the screen: not my main one.
    func canDelete(_ page: PlanetPage) -> Bool {
        if case .own = page { return page != mainPlanet }
        return true
    }

    /// Deletes my planet together with its places. The main one cannot be deleted.
    func deleteOwnPlanet(_ page: PlanetPage) throws {
        guard case .own = page, page != mainPlanet, let map = map(id: page.mapID) else { return }
        context.delete(map)
        try commit()
    }

    /// A friend's planet appears in the "Friends Marks" grid.
    func add(_ page: PlanetPage) throws {
        guard case .friend = page, let map = map(id: page.mapID) else { return }
        map.isAdded = true
        try commit()
    }

    /// Removes a friend's planet from the screen; the snapshot stays and it can be added again.
    func removeFromScreen(_ page: PlanetPage) throws {
        guard case .friend = page, let map = map(id: page.mapID) else { return }
        map.isAdded = false
        try commit()
    }

    /// Saves and re-reads immediately: the screen changes in the same transaction as the gesture
    /// animation. The shared save subscription fires later and only confirms the same state.
    private func commit() throws {
        defer { reload() }
        try persistence.save()
    }

    private func map(id: UUID) -> MemoryMap? {
        let request = MemoryMap.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
