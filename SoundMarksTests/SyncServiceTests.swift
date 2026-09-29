import CoreData
import Foundation
import Testing

@testable import SoundMarks

/// Two devices exchange maps via a `.soundmap` file.
@Suite("Sync between devices")
@MainActor
struct SyncServiceTests {
    /// One "device": its own store, its own profile.
    @MainActor
    private struct Device {
        let persistence: PersistenceController
        let profiles: ProfileStore
        let sync: SyncService

        init(nickname: String) throws {
            persistence = PersistenceController(mode: .inMemory)
            profiles = ProfileStore(persistence: persistence)
            sync = SyncService(persistence: persistence, profiles: profiles, photos: UnavailablePhotoService())
            try profiles.createMe(nickname: nickname, avatarColorHex: "#FF3366", avatarData: nil)
        }

        var meDTO: ProfileDTO {
            get throws { try #require(profiles.me.flatMap(profiles.dto(for:))) }
        }

        @discardableResult
        func addPlace(title: String, to map: MemoryMap? = nil) throws -> Place {
            let context = persistence.viewContext
            let place = Place(context: context)
            place.map = try map ?? persistence.ensurePersonalMap()
            place.latitude = 52.52
            place.longitude = 13.40
            place.eventDate = EventDate(year: 2024, month: 5, day: 1)
            let track = Track(context: context)
            track.title = title
            track.artist = "Artist"
            place.track = track
            try persistence.save()
            return place
        }

        func titles(in scope: PlaceScope) throws -> [String] {
            try persistence.viewContext.fetch(Place.fetchRequest(scope: scope))
                .compactMap { $0.track?.title }
                .sorted()
        }

        /// Sending through a real file: writing and reading the archive.
        func send(_ snapshot: (SoundmapManifest, [String: Data]), to other: Device) throws -> SyncSummary {
            let data = try SoundmapFile.write(manifest: snapshot.0, files: snapshot.1)
            let (manifest, files) = try SoundmapFile.read(data)
            return try other.sync.apply(manifest, files: files)
        }
    }

    private func befriend(_ a: Device, _ b: Device) throws {
        try a.profiles.upsert(try b.meDTO, status: .friend)
        try b.profiles.upsert(try a.meDTO, status: .friend)
    }

    @Test("New profile: the planet is visible to friends by default")
    func newProfileIsVisible() throws {
        let anna = try Device(nickname: "Anna")
        #expect(anna.profiles.me?.planetVisible == true)
    }

    @Test("Friend planets appear on the screen only after \"Add Planet\"")
    func friendPlanetsNeedAdding() async throws {
        let anna = try Device(nickname: "Anna")
        let ben = try Device(nickname: "Ben")
        let cleo = try Device(nickname: "Cleo")
        try befriend(anna, ben)
        try befriend(anna, cleo)
        try ben.addPlace(title: "Ben")
        try cleo.addPlace(title: "Cleo")
        _ = try ben.send(try await ben.sync.planetSnapshot(), to: anna)
        _ = try cleo.send(try await cleo.sync.planetSnapshot(), to: anna)
        let benProfile = try #require(anna.profiles.friends.first { $0.nickname == "Ben" })
        try anna.sync.createSharedMap(with: benProfile)

        let directory = PlanetDirectory(persistence: anna.persistence, profiles: anna.profiles)
        // Paired — to the left of mine, friend planets are only available to add for now.
        #expect(directory.sharedPlanets.count == 1)
        #expect(directory.friendStacks.isEmpty)
        #expect(directory.availableStacks.map(\.nickname).sorted() == ["Ben", "Cleo"])
        let mainTitle = directory.info(for: directory.mainPlanet)?.title
        #expect(mainTitle != nil)

        let benPlanet = try #require(directory.availableStacks.first { $0.nickname == "Ben" }?.planets.first)
        #expect(benPlanet.title.contains("Ben"))
        #expect(benPlanet.placeCount == 1)
        try directory.add(benPlanet.page)
        #expect(directory.friendStacks.map(\.nickname) == ["Ben"])
        #expect(directory.friendsPlaceCount == 1)

        // A blocked friend disappears everywhere.
        let cleoProfile = try #require(anna.profiles.friends.first { $0.nickname == "Cleo" })
        try anna.profiles.block(cleoProfile)
        try anna.persistence.save()
        directory.reload()
        #expect(!directory.availableStacks.contains { $0.nickname == "Cleo" })
    }

    @Test("Several own planets: at the friend's they lie in a stack, captions are kept")
    func severalOwnPlanets() async throws {
        let anna = try Device(nickname: "Anna")
        let ben = try Device(nickname: "Ben")
        try befriend(anna, ben)
        try ben.addPlace(title: "Home")
        let benDirectory = PlanetDirectory(persistence: ben.persistence, profiles: ben.profiles)
        let italy = try benDirectory.createOwnPlanet(named: "Italy 2025")
        let italyMap = try #require(ben.sync.map(id: italy.mapID))
        try ben.addPlace(title: "Rome", to: italyMap)
        #expect(benDirectory.ownPlanets.count == 2)

        for snapshot in try await ben.sync.planetSnapshots() {
            _ = try ben.send(snapshot, to: anna)
        }

        let directory = PlanetDirectory(persistence: anna.persistence, profiles: anna.profiles)
        let stack = try #require(directory.availableStacks.first)
        #expect(stack.planets.contains { $0.title == "Italy 2025" })
        #expect(stack.planets.contains { $0.title.contains("Ben") })
        for planet in stack.planets { try directory.add(planet.page) }
        #expect(directory.friendStacks.first?.planets.count == 2)
        #expect(directory.friendsPlaceCount == 2)

        // My caption for someone else's planet — only on my side.
        let italyAtAnna = try #require(directory.friendStacks.first?.planets.first { $0.title == "Italy 2025" })
        try directory.rename(italyAtAnna.page, to: "Ben's Italy")
        #expect(directory.info(for: italyAtAnna.page)?.title == "Ben's Italy")
    }

    @Test("Planets swap places with neighbors; the main one cannot be deleted")
    func reorderAndDelete() async throws {
        let anna = try Device(nickname: "Anna")
        let directory = PlanetDirectory(persistence: anna.persistence, profiles: anna.profiles)
        let italy = try directory.createOwnPlanet(named: "Italy")
        let spain = try directory.createOwnPlanet(named: "Spain")
        #expect(directory.ownPlanets.map(\.page) == [directory.mainPlanet, italy, spain])

        #expect(directory.move(spain, by: -1))
        #expect(directory.ownPlanets.map(\.page) == [directory.mainPlanet, spain, italy])
        #expect(directory.move(spain, by: -1))
        #expect(directory.ownPlanets.first?.page == spain)
        // Nowhere further to go.
        #expect(!directory.move(spain, by: -1))
        // The main one stays main wherever it is.
        #expect(directory.mainPlanet != spain)
        #expect(!directory.canDelete(directory.mainPlanet))
        #expect(directory.canDelete(italy))

        try directory.deleteOwnPlanet(italy)
        #expect(directory.ownPlanets.count == 2)
    }

    @Test("A paired planet can be deleted on my side, friends' stacks can be reordered")
    func sharedAndStacks() async throws {
        let anna = try Device(nickname: "Anna")
        let ben = try Device(nickname: "Ben")
        let cleo = try Device(nickname: "Cleo")
        try befriend(anna, ben)
        try befriend(anna, cleo)
        try ben.addPlace(title: "Ben")
        try cleo.addPlace(title: "Cleo")
        _ = try ben.send(try await ben.sync.planetSnapshot(), to: anna)
        _ = try cleo.send(try await cleo.sync.planetSnapshot(), to: anna)

        let directory = PlanetDirectory(persistence: anna.persistence, profiles: anna.profiles)
        for stack in directory.availableStacks {
            for planet in stack.planets { try directory.add(planet.page) }
        }
        let order = directory.friendStacks.map(\.nickname)
        #expect(order.count == 2)
        let lastID = try #require(directory.friendStacks.last?.ownerID)
        directory.moveStack(ownerID: lastID, to: 0)
        #expect(directory.friendStacks.map(\.nickname) == order.reversed())

        try directory.removeStackFromScreen(ownerID: lastID)
        directory.reload()
        #expect(directory.friendStacks.count == 1)

        let benProfile = try #require(anna.profiles.friends.first { $0.nickname == "Ben" })
        try anna.sync.createSharedMap(with: benProfile)
        directory.reload()
        let paired = try #require(directory.sharedPlanets.first?.page)
        try directory.deleteShared(paired)
        directory.reload()
        #expect(directory.sharedPlanets.isEmpty)
    }

    @Test("A friend's planet arrives as a snapshot and is shown separately from mine")
    func planetArrives() async throws {
        let anna = try Device(nickname: "Anna")
        let ben = try Device(nickname: "Ben")
        try befriend(anna, ben)
        try anna.profiles.updateMe(planetVisible: true)
        try anna.addPlace(title: "Instant Crush")
        try ben.addPlace(title: "My track")

        let summary = try anna.send(try await anna.sync.planetSnapshot(), to: ben)
        #expect(summary.added == 1)

        let annaPlanet = try #require(ben.sync.friendPlanets().first)
        #expect(try ben.titles(in: .map(try #require(annaPlanet.id))) == ["Instant Crush"])
        // My planet at Ben's didn't mix with Anna's.
        #expect(try ben.titles(in: .mine) == ["My track"])
    }

    @Test("A hidden planet cannot be sent")
    func hiddenPlanetNotExported() async throws {
        let anna = try Device(nickname: "Anna")
        try anna.profiles.updateMe(planetVisible: false)
        await #expect(throws: SyncService.Failure.planetHidden) {
            _ = try await anna.sync.planetSnapshot()
        }
    }

    @Test("Turning visibility off deletes my planet at the friend's")
    func hidingRemovesPlanet() async throws {
        let anna = try Device(nickname: "Anna")
        let ben = try Device(nickname: "Ben")
        try befriend(anna, ben)
        try anna.profiles.updateMe(planetVisible: true)
        try anna.addPlace(title: "Song")
        _ = try anna.send(try await anna.sync.planetSnapshot(), to: ben)
        #expect(ben.sync.friendPlanets().count == 1)

        try anna.profiles.updateMe(planetVisible: false)
        let summary = try anna.send(try anna.sync.hiddenPlanetNotice(), to: ben)
        #expect(summary.planetHidden)
        #expect(ben.sync.friendPlanets().isEmpty)
    }

    @Test("A file from a stranger is rejected")
    func strangerRejected() async throws {
        let anna = try Device(nickname: "Anna")
        let mallory = try Device(nickname: "Mallory")
        try anna.profiles.upsert(try mallory.meDTO, status: .friend)
        try mallory.profiles.updateMe(planetVisible: true)
        try mallory.addPlace(title: "Spam")

        // Mallory isn't in Anna's friends on her side — but we check the recipient: Ben doesn't know her.
        let ben = try Device(nickname: "Ben")
        let snapshot = try await mallory.sync.planetSnapshot()
        #expect(throws: SyncService.Failure.notFriend) {
            _ = try mallory.send(snapshot, to: ben)
        }
    }

    @Test("A file from a blocked friend is rejected")
    func blockedRejected() async throws {
        let anna = try Device(nickname: "Anna")
        let ben = try Device(nickname: "Ben")
        try befriend(anna, ben)
        try anna.profiles.updateMe(planetVisible: true)
        try anna.addPlace(title: "Song")
        let annaOnBen = try #require(ben.profiles.profile(id: try anna.meDTO.id))
        try ben.profiles.block(annaOnBen)

        let snapshot = try await anna.sync.planetSnapshot()
        #expect(throws: SyncService.Failure.notFriend) {
            _ = try anna.send(snapshot, to: ben)
        }
    }

    @Test("Shared map: both add places, a deletion reaches the friend")
    func sharedMapRoundTrip() async throws {
        let anna = try Device(nickname: "Anna")
        let ben = try Device(nickname: "Ben")
        try befriend(anna, ben)

        let benOnAnna = try #require(anna.profiles.profile(id: try ben.meDTO.id))
        let shared = try anna.sync.createSharedMap(with: benOnAnna)
        let mapID = try #require(shared.id)
        let annaPlace = try anna.addPlace(title: "From Anna", to: shared)

        // Anna → Ben: Ben gets the shared map.
        _ = try anna.send(try await anna.sync.sharedMapSnapshot(mapID: mapID), to: ben)
        let benShared = try #require(ben.sync.map(id: mapID))
        try ben.addPlace(title: "From Ben", to: benShared)

        // Ben → Anna: Anna has both places.
        _ = try ben.send(try await ben.sync.sharedMapSnapshot(mapID: mapID), to: anna)
        #expect(try anna.titles(in: .map(mapID)) == ["From Anna", "From Ben"])

        // Anna deletes her place — after the exchange it's gone at Ben's too.
        try await Task.sleep(for: .milliseconds(1100))
        annaPlace.markDeleted()
        try anna.persistence.save()
        let summary = try anna.send(try await anna.sync.sharedMapSnapshot(mapID: mapID), to: ben)
        #expect(summary.removed == 1)
        #expect(try ben.titles(in: .map(mapID)) == ["From Ben"])
    }

    @Test("Sending again duplicates nothing")
    func idempotent() async throws {
        let anna = try Device(nickname: "Anna")
        let ben = try Device(nickname: "Ben")
        try befriend(anna, ben)
        try anna.profiles.updateMe(planetVisible: true)
        try anna.addPlace(title: "Song")

        let snapshot = try await anna.sync.planetSnapshot()
        _ = try anna.send(snapshot, to: ben)
        let second = try anna.send(snapshot, to: ben)
        #expect(second.added == 0 && second.updated == 0)
        let planet = try #require(ben.sync.friendPlanets().first?.id)
        #expect(try ben.titles(in: .map(planet)).count == 1)
    }
}

/// Friend code.
@Suite("FriendCode")
struct FriendCodeTests {
    @Test("8 characters without look-alikes")
    func format() {
        for _ in 0..<50 {
            let code = FriendCode.generate()
            #expect(code.count == 8)
            #expect(FriendCode.isValid(code))
            #expect(!code.contains("0") && !code.contains("O") && !code.contains("1") && !code.contains("I"))
        }
    }

    @Test("Typing by hand: case, spaces and dashes do not matter")
    func normalization() {
        #expect(FriendCode.normalized(" abcd-efgh ") == "ABCDEFGH")
        #expect(FriendCode.isValid("abcd efgh"))
        #expect(!FriendCode.isValid("ABCD"))
    }

    @Test("The QR contains the code and reads back")
    func qrRoundTrip() {
        #expect(FriendCode.code(fromQR: FriendCode.qrPayload(for: "ABCDEFGH")) == "ABCDEFGH")
        #expect(FriendCode.code(fromQR: "https://example.com") == nil)
    }
}

/// The handshake when adding a nearby friend: no endless waiting for each other.
@Suite("Adding a nearby friend")
@MainActor
struct FriendHandshakeTests {
    private let small = "AAAA2222"
    private let big = "ZZZZ9999"

    @Test("A stranger gets the request shown")
    func strangerAsks() {
        #expect(FriendHandshake.decide(senderCode: big, myCode: small, state: .idle,
                                       isBlocked: false, isFriend: false) == .ask)
    }

    @Test("A blocked person is always rejected")
    func blockedDeclined() {
        #expect(FriendHandshake.decide(senderCode: big, myCode: small, state: .searching(code: big),
                                       isBlocked: true, isFriend: false) == .decline)
    }

    @Test("Crossing invitations: exactly one side accepts")
    func crossingInvitations() {
        // Each waits for the other to confirm.
        let fromBig = FriendHandshake.decide(senderCode: big, myCode: small,
                                             state: .waitingForConfirmation(code: big, nickname: "B"),
                                             isBlocked: false, isFriend: false)
        let fromSmall = FriendHandshake.decide(senderCode: small, myCode: big,
                                               state: .waitingForConfirmation(code: small, nickname: "A"),
                                               isBlocked: false, isFriend: false)
        #expect(fromBig == .decline)
        #expect(fromSmall == .accept)
    }

    @Test("I'm looking for exactly this person — accept without asking")
    func searchingAccepts() {
        #expect(FriendHandshake.decide(senderCode: small, myCode: big, state: .searching(code: small),
                                       isBlocked: false, isFriend: false) == .accept)
    }

    @Test("Already a friend — do not ask again")
    func existingFriendAccepts() {
        #expect(FriendHandshake.decide(senderCode: big, myCode: small, state: .idle,
                                       isBlocked: false, isFriend: true) == .accept)
    }
}
