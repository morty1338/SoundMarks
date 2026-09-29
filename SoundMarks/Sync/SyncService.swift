import CoreData
import Foundation
import UIKit

/// Import result — to honestly tell the user what changed.
struct SyncSummary: Equatable, Sendable {
    var senderName: String
    var kind: MapDTO.Kind
    var added = 0
    var updated = 0
    var removed = 0
    /// The friend hid their planet — its snapshot was deleted on our side.
    var planetHidden = false
}

/// Map exchange with friends: building a snapshot and applying an incoming one.
/// The same format for both MultipeerConnectivity and the `.soundmap` file.
@MainActor
final class SyncService {
    enum Failure: LocalizedError, Equatable {
        case noProfile
        case planetHidden
        case notFriend
        case notParticipant
        case mapNotFound

        var errorDescription: String? {
            switch self {
            case .noProfile:
                String(localized: "sync.error.noProfile", defaultValue: "Create your profile on the Friends screen first.")
            case .planetHidden:
                String(localized: "sync.error.planetHidden",
                       defaultValue: "Your planet is hidden from friends. Turn on visibility in Settings.")
            case .notFriend:
                String(localized: "sync.error.notFriend",
                       defaultValue: "This file is from someone who isn't your friend.")
            case .notParticipant:
                String(localized: "sync.error.notParticipant", defaultValue: "You're not a participant of this shared map.")
            case .mapNotFound:
                String(localized: "sync.error.mapNotFound", defaultValue: "Map not found.")
            }
        }
    }

    private let persistence: PersistenceController
    private let profiles: ProfileStore
    private let photos: any PhotoService

    /// Photo size in the exchange file: enough for a phone screen, without extra weight.
    private let photoSide: CGFloat = 1280

    init(persistence: PersistenceController, profiles: ProfileStore, photos: any PhotoService) {
        self.persistence = persistence
        self.profiles = profiles
        self.photos = photos
    }

    private var context: NSManagedObjectContext { persistence.viewContext }

    // MARK: - Maps

    func sharedMaps() -> [MemoryMap] {
        let request = MemoryMap.fetchRequest()
        request.predicate = NSPredicate(format: "kindRaw == %@", MemoryMapKind.shared.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    func friendPlanets() -> [MemoryMap] {
        let request = MemoryMap.fetchRequest()
        request.predicate = NSPredicate(format: "kindRaw == %@", MemoryMapKind.friend.rawValue)
        return (try? context.fetch(request)) ?? []
    }

    func map(id: UUID) -> MemoryMap? {
        let request = MemoryMap.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// A shared map with a friend. It appears on their side after the first sync.
    @discardableResult
    func createSharedMap(with friend: Profile) throws -> MemoryMap {
        guard let me = profiles.me, let myID = me.id, let friendID = friend.id else { throw Failure.noProfile }
        let map = MemoryMap(context: context)
        map.kind = .shared
        map.name = String(localized: "sharedMap.defaultName",
                          defaultValue: "You and \(friend.nickname ?? "")")
        map.ownerProfileId = myID
        map.participantIDs = [myID, friendID]
        map.updatedAt = Date()
        try persistence.save()
        return map
    }

    // MARK: - Export

    /// My main planet — only if visibility is on.
    func planetSnapshot(since: Date? = nil) async throws -> (SoundmapManifest, [String: Data]) {
        try await planetSnapshot(of: try persistence.ensurePersonalMap(), since: since)
    }

    /// All my planets: everyone can have several, with captions.
    func planetSnapshots(since: Date? = nil) async throws -> [(SoundmapManifest, [String: Data])] {
        var result: [(SoundmapManifest, [String: Data])] = []
        for map in try persistence.ownPlanets() {
            result.append(try await planetSnapshot(of: map, since: since))
        }
        return result
    }

    private func planetSnapshot(of map: MemoryMap, since: Date?) async throws -> (SoundmapManifest, [String: Data]) {
        guard let me = profiles.me, let meDTO = profiles.dto(for: me), let myID = me.id else {
            throw Failure.noProfile
        }
        guard me.planetVisible else { throw Failure.planetHidden }
        // The main planet without a caption goes without a name — for the friend it becomes "[nick]'s Planet".
        let isMain = (try? persistence.ensurePersonalMap()) == map
        let mapDTO = MapDTO(id: map.id ?? UUID(),
                            name: isMain && map.title == nil ? "" : (map.title ?? map.name ?? ""),
                            kind: .planet,
                            ownerProfileId: myID,
                            participantIDs: [myID],
                            updatedAt: map.updatedAt ?? Date())
        return try await snapshot(of: map, as: mapDTO, sender: meDTO, avatar: me.avatarData, since: since)
    }

    /// The "my planet is hidden" notice — friends delete its snapshot.
    func hiddenPlanetNotice() throws -> (SoundmapManifest, [String: Data]) {
        guard let me = profiles.me, let meDTO = profiles.dto(for: me), let myID = me.id else {
            throw Failure.noProfile
        }
        let mapDTO = MapDTO(id: UUID(), name: "", kind: .planet, ownerProfileId: myID,
                            participantIDs: [myID], updatedAt: Date())
        return (SoundmapManifest(createdAt: Date(), sender: meDTO, map: mapDTO, places: []), [:])
    }

    func sharedMapSnapshot(mapID: UUID, since: Date? = nil) async throws -> (SoundmapManifest, [String: Data]) {
        guard let me = profiles.me, let meDTO = profiles.dto(for: me) else { throw Failure.noProfile }
        guard let map = map(id: mapID), map.kind == .shared else { throw Failure.mapNotFound }
        let mapDTO = MapDTO(id: mapID,
                            name: map.name ?? "",
                            kind: .shared,
                            ownerProfileId: map.ownerProfileId ?? UUID(),
                            participantIDs: map.participantIDs,
                            updatedAt: map.updatedAt ?? Date())
        return try await snapshot(of: map, as: mapDTO, sender: meDTO, avatar: me.avatarData, since: since)
    }

    /// A file for sending remotely: AirDrop, messengers.
    func exportFile(_ snapshot: (SoundmapManifest, [String: Data])) throws -> URL {
        let data = try SoundmapFile.write(manifest: snapshot.0, files: snapshot.1)
        let stamp = snapshot.0.createdAt.formatted(.iso8601.year().month().day())
        // Several planets are sent at once — each file gets its own name.
        let parts = [snapshot.0.sender.nickname.isEmpty ? "SoundMarks" : snapshot.0.sender.nickname,
                     snapshot.0.map.name, stamp]
        let name = parts.filter { !$0.isEmpty }.joined(separator: " ")
            .replacingOccurrences(of: "/", with: "-")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("soundmap", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name).appendingPathExtension(SoundmapFile.fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func snapshot(of map: MemoryMap,
                          as mapDTO: MapDTO,
                          sender: ProfileDTO,
                          avatar: Data?,
                          since: Date?) async throws -> (SoundmapManifest, [String: Data]) {
        var files: [String: Data] = [:]
        var senderDTO = sender
        if let avatar, let jpeg = UIImage(data: avatar)?.jpegData(compressionQuality: 0.8) {
            files["avatar.jpg"] = jpeg
            senderDTO.avatarFile = "avatar.jpg"
        }

        let places = (map.places ?? []).filter { place in
            guard let since else { return true }
            return (place.updatedAt ?? .distantPast) > since
        }

        var dtos: [PlaceDTO] = []
        for place in places {
            guard let dto = await dto(for: place, files: &files) else { continue }
            dtos.append(dto)
        }

        let manifest = SoundmapManifest(createdAt: Date(), sender: senderDTO, map: mapDTO, places: dtos)
        return (manifest, files)
    }

    private func dto(for place: Place, files: inout [String: Data]) async -> PlaceDTO? {
        guard let id = place.id else { return nil }

        var media: [MediaDTO] = []
        if !place.isTombstoned {
            for item in place.orderedMedia {
                guard let mediaID = item.id else { continue }
                let path = "photos/\(mediaID.uuidString).jpg"
                if let jpeg = await jpeg(for: item) {
                    files[path] = jpeg
                }
                media.append(MediaDTO(id: mediaID,
                                      kind: item.kind.rawValue,
                                      takenAt: item.takenAt,
                                      order: Int(item.order),
                                      file: files[path] == nil ? nil : path))
            }
        }

        let track = place.track.flatMap { track -> TrackDTO? in
            guard let title = track.title else { return nil }
            return TrackDTO(title: title, artist: track.artist ?? "", album: track.album,
                            artworkURL: track.artworkURL, previewURL: track.previewURL,
                            spotifyURI: track.spotifyURI, source: track.source.rawValue)
        }

        return PlaceDTO(id: id,
                        latitude: place.latitude,
                        longitude: place.longitude,
                        placeName: place.placeName,
                        city: place.city,
                        country: place.country,
                        createdAt: place.createdAt ?? Date(),
                        updatedAt: place.updatedAt ?? place.createdAt ?? Date(),
                        eventYear: Int(place.eventYear),
                        eventMonth: place.eventMonth == 0 ? nil : Int(place.eventMonth),
                        eventDay: place.eventDay == 0 ? nil : Int(place.eventDay),
                        note: place.note,
                        authorProfileId: place.authorProfileId ?? profiles.me?.id,
                        isTombstoned: place.isTombstoned,
                        track: track,
                        media: media,
                        skinID: place.skinID)
    }

    /// A compressed JPEG: from the store copy or from the library. For a video — the preview frame.
    private func jpeg(for item: MediaItem) async -> Data? {
        var source = item.imageData
        if source == nil, let identifier = item.localIdentifier {
            source = try? await photos.imageData(for: identifier,
                                                 targetSize: CGSize(width: photoSide, height: photoSide))
        }
        guard let source, let image = UIImage(data: source) else { return nil }
        return image.jpegData(compressionQuality: 0.72)
    }

    // MARK: - Import

    @discardableResult
    func importFile(at url: URL) throws -> SyncSummary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let (manifest, files) = try SoundmapFile.read(try Data(contentsOf: url))
        return try apply(manifest, files: files)
    }

    /// Applies a snapshot from a friend. Rejects strangers and blocked people.
    @discardableResult
    func apply(_ manifest: SoundmapManifest, files: [String: Data]) throws -> SyncSummary {
        guard let me = profiles.me, let myID = me.id else { throw Failure.noProfile }
        guard let sender = profiles.trustedFriend(id: manifest.sender.id) else { throw Failure.notFriend }

        // Update the friend's profile: nickname, color, avatar, visibility.
        sender.nickname = manifest.sender.nickname
        sender.avatarColorHex = manifest.sender.avatarColorHex
        sender.planetVisible = manifest.sender.planetVisible
        if let file = manifest.sender.avatarFile, let avatar = files[file] {
            sender.avatarData = avatar
        }

        var summary = SyncSummary(senderName: manifest.sender.nickname, kind: manifest.map.kind)

        let map: MemoryMap
        switch manifest.map.kind {
        case .planet:
            guard manifest.sender.planetVisible else {
                profiles.deleteFriendPlanet(ownerID: manifest.sender.id)
                try persistence.save()
                profiles.markSynced(sender)
                summary.planetHidden = true
                return summary
            }
            map = friendPlanet(for: manifest)

        case .shared:
            guard manifest.map.participantIDs.contains(myID) else { throw Failure.notParticipant }
            map = sharedMap(for: manifest)
        }

        let local = (map.places ?? []).compactMap(Self.comparisonDTO(for:))
        let plan = MapMerger.plan(local: local, incoming: manifest.places)
        let knownIDs = Set(local.map(\.id))

        for dto in plan.apply {
            if dto.isTombstoned {
                summary.removed += knownIDs.contains(dto.id) ? 1 : 0
            } else if knownIDs.contains(dto.id) {
                summary.updated += 1
            } else {
                summary.added += 1
            }
            upsert(dto, into: map, files: files)
        }

        map.lastSyncedAt = Date()
        try persistence.save()
        profiles.markSynced(sender)
        return summary
    }

    /// A friend's planet by its id: a friend may have several.
    /// A new planet does not appear on the screen — it is added via "Add Planet".
    private func friendPlanet(for manifest: SoundmapManifest) -> MemoryMap {
        let request = MemoryMap.fetchRequest()
        request.predicate = NSPredicate(format: "kindRaw == %@ AND id == %@",
                                        MemoryMapKind.friend.rawValue, manifest.map.id as CVarArg)
        request.fetchLimit = 1
        let map = (try? context.fetch(request).first) ?? {
            let created = MemoryMap(context: context)
            created.id = manifest.map.id
            created.kind = .friend
            created.ownerProfileId = manifest.sender.id
            return created
        }()
        // The planet name is set by the friend; my caption is stored separately in `title`.
        map.name = manifest.map.name
        map.ownerName = manifest.sender.nickname
        map.updatedAt = manifest.map.updatedAt
        return map
    }

    private func sharedMap(for manifest: SoundmapManifest) -> MemoryMap {
        if let existing = map(id: manifest.map.id) { return existing }
        let map = MemoryMap(context: context)
        map.id = manifest.map.id
        map.kind = .shared
        map.name = manifest.map.name
        map.ownerProfileId = manifest.map.ownerProfileId
        map.participantIDs = manifest.map.participantIDs
        map.updatedAt = manifest.map.updatedAt
        return map
    }

    private func upsert(_ dto: PlaceDTO, into map: MemoryMap, files: [String: Data]) {
        let request = Place.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", dto.id as CVarArg)
        request.fetchLimit = 1
        let place = (try? context.fetch(request).first) ?? Place(context: context)

        place.id = dto.id
        place.map = map
        place.latitude = dto.latitude
        place.longitude = dto.longitude
        place.placeName = dto.placeName
        place.city = dto.city
        place.country = dto.country
        place.createdAt = dto.createdAt
        place.eventDate = EventDate(year: dto.eventYear, month: dto.eventMonth, day: dto.eventDay)
        place.authorProfileId = dto.authorProfileId
        place.skinID = dto.skinID

        if dto.isTombstoned {
            place.markDeleted(at: dto.updatedAt)
        } else {
            place.isTombstoned = false
            place.note = dto.note

            if let trackDTO = dto.track {
                let track = place.track ?? Track(context: context)
                track.title = trackDTO.title
                track.artist = trackDTO.artist
                track.album = trackDTO.album
                track.artworkURL = trackDTO.artworkURL
                track.previewURL = trackDTO.previewURL
                track.spotifyURI = trackDTO.spotifyURI
                track.sourceRaw = trackDTO.source
                place.track = track
            }

            // The friend's photos are stored as copies: we have no access to their library.
            (place.media ?? []).forEach(context.delete)
            for mediaDTO in dto.media {
                let item = MediaItem(context: context)
                item.id = mediaDTO.id
                item.typeRaw = mediaDTO.kind
                item.takenAt = mediaDTO.takenAt
                item.order = Int16(clamping: mediaDTO.order)
                item.imageData = mediaDTO.file.flatMap { files[$0] }
                item.place = place
            }
        }

        // Edit time as the sender's, otherwise merging on the next exchange goes wrong.
        place.updatedAt = dto.updatedAt
    }

    /// For merging with local places only the UUID and edit time matter.
    private static func comparisonDTO(for place: Place) -> PlaceDTO? {
        guard let id = place.id else { return nil }
        return PlaceDTO(id: id, latitude: 0, longitude: 0, placeName: nil, city: nil, country: nil,
                        createdAt: place.createdAt ?? .distantPast,
                        updatedAt: place.updatedAt ?? .distantPast,
                        eventYear: 0, eventMonth: nil, eventDay: nil, note: nil,
                        authorProfileId: nil, isTombstoned: place.isTombstoned, track: nil, media: [])
    }
}
