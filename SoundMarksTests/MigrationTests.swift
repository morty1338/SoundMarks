import CoreData
import Foundation
import Testing

@testable import SoundMarks

/// A store created by the Phase 1 build opens with the current model without data loss.
///
/// The fixture is a real database from the simulator: 4 places, 4 tracks, 3 media, a personal map.
/// The user's phone already holds places — recreating the database on update is not allowed.
@Suite("Store migration")
@MainActor
struct MigrationTests {
    private func copyFixture() throws -> URL {
        let bundle = Bundle(for: FixtureLocator.self)
        let source = try #require(bundle.url(forResource: "phase1-store", withExtension: "sqlite"))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("SoundMarks-local.sqlite")
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    @Test("The Phase 1 database opens and migrates")
    func phaseOneStoreMigrates() throws {
        let url = try copyFixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let controller = PersistenceController(mode: .file(url))
        #expect(controller.loadFailure == nil)

        let context = controller.viewContext
        #expect(try context.count(for: Place.fetchRequest()) == 4)
        #expect(try context.count(for: Track.fetchRequest()) == 4)
        #expect(try context.count(for: MediaItem.fetchRequest()) == 3)
    }

    @Test("The existing map is personal after migration")
    func existingMapBecomesOwn() throws {
        let url = try copyFixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let controller = PersistenceController(mode: .file(url))
        let maps = try controller.viewContext.fetch(MemoryMap.fetchRequest())
        #expect(maps.count == 1)
        #expect(maps.first?.kind == .own)
        // Looking up the personal map again doesn't create a second one.
        let own = try controller.ensurePersonalMap()
        #expect(own.objectID == maps.first?.objectID)
    }

    @Test("The database is writable after migration")
    func migratedStoreIsWritable() throws {
        let url = try copyFixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let controller = PersistenceController(mode: .file(url))
        let place = try #require(try controller.viewContext.fetch(Place.fetchRequest()).first)
        place.city = "Berlin"
        place.country = "Deutschland"
        try controller.save()

        let reopened = PersistenceController(mode: .file(url))
        let request = Place.fetchRequest()
        request.predicate = NSPredicate(format: "city == %@", "Berlin")
        #expect(try reopened.viewContext.count(for: request) == 1)
    }
}

/// Anchor for finding the test bundle.
private final class FixtureLocator {}
