import CoreData
import Foundation
import Testing

@testable import SoundMarks

/// Checks that the Core Data model loads and relationships work.
@Suite("Persistence")
@MainActor
struct PersistenceTests {
    private func makeController() -> PersistenceController {
        PersistenceController(mode: .inMemory)
    }

    @Test("The in-memory store opens")
    func inMemoryStoreLoads() {
        let controller = makeController()
        #expect(controller.loadFailure == nil)
        #expect(controller.container.persistentStoreCoordinator.persistentStores.isEmpty == false)
    }

    @Test("The personal map is created once")
    func personalMapIsCreatedOnce() throws {
        let controller = makeController()
        let first = try controller.ensurePersonalMap()
        let second = try controller.ensurePersonalMap()
        #expect(first.objectID == second.objectID)
        #expect(first.kind == .own)
    }

    @Test("A place fills in id and createdAt itself")
    func placeAutoFillsIdentity() throws {
        let controller = makeController()
        let place = Place(context: controller.viewContext)
        #expect(place.id != nil)
        #expect(place.createdAt != nil)
    }

    @Test("A place links to a track, media and a map")
    func placeRelationships() throws {
        let controller = makeController()
        let map = try controller.ensurePersonalMap()

        let place = Place(context: controller.viewContext)
        place.coordinate = .init(latitude: 41.3874, longitude: 2.1686)
        place.placeName = "Barcelona"
        place.eventDate = EventDate(year: 2023, month: 8, day: 14)
        place.map = map

        let track = Track(context: controller.viewContext)
        track.title = "Song"
        track.artist = "Artist"
        track.source = .spotifyExport
        place.track = track

        let second = MediaItem(context: controller.viewContext)
        second.order = 1
        second.kind = .video
        second.place = place

        let first = MediaItem(context: controller.viewContext)
        first.order = 0
        first.kind = .photo
        first.place = place

        try controller.save()

        #expect(place.track?.source == .spotifyExport)
        #expect(place.orderedMedia.map(\.kind) == [.photo, .video])
        #expect(map.places?.contains(place) == true)
        #expect(place.eventDate == EventDate(year: 2023, month: 8, day: 14))
    }

    @Test("A place's pin style overrides the global one")
    func pinStyleOverride() {
        let controller = makeController()
        let place = Place(context: controller.viewContext)
        #expect(place.pinStyle(fallback: .vinyl) == .vinyl)
        place.pinStyleOverride = .turntable
        #expect(place.pinStyle(fallback: .vinyl) == .turntable)
    }

    @Test("The geofence is returned only when monitoring is on")
    func geofenceRegionRespectsToggle() {
        let controller = makeController()
        let place = Place(context: controller.viewContext)
        place.geofenceEnabled = true
        place.coordinate = .init(latitude: 52.52, longitude: 13.405)
        #expect(place.geofenceRegion != nil)

        place.geofenceEnabled = false
        #expect(place.geofenceRegion == nil)
    }
}

/// Deletion is a marker for sync; selections don't see it.
@Suite("Place selection scopes")
@MainActor
struct PlaceScopeTests {
    @Test("A deleted place stays as a marker and disappears from selections")
    func tombstoneHidden() throws {
        let controller = PersistenceController(mode: .inMemory)
        let context = controller.viewContext
        let map = try controller.ensurePersonalMap()

        let place = Place(context: context)
        place.map = map
        let track = Track(context: context)
        place.track = track
        try controller.save()

        place.markDeleted()
        try controller.save()

        #expect(try context.count(for: Place.fetchRequest()) == 1)
        #expect(try context.count(for: Place.fetchRequest(scope: .mine)) == 0)
        #expect(try context.count(for: Track.fetchRequest()) == 0)
        #expect(place.isTombstoned)
    }

    @Test("My planet, a friend's map and a shared map don't mix")
    func scopesSeparateMaps() throws {
        let controller = PersistenceController(mode: .inMemory)
        let context = controller.viewContext
        let mine = try controller.ensurePersonalMap()

        let friendMap = MemoryMap(context: context)
        friendMap.kind = .friend
        let sharedMap = MemoryMap(context: context)
        sharedMap.kind = .shared

        for map in [mine, friendMap, sharedMap] {
            let place = Place(context: context)
            place.map = map
        }
        try controller.save()

        #expect(try context.count(for: Place.fetchRequest(scope: .mine)) == 1)
        #expect(try context.count(for: Place.fetchRequest(scope: .map(try #require(friendMap.id)))) == 1)
        // Reminders — about my and shared places, but not about a snapshot of a friend's map.
        #expect(try context.count(for: Place.fetchRequest(scope: .remindable)) == 2)
    }
}
