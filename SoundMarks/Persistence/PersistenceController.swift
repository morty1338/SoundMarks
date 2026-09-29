import CoreData
import Foundation

/// Local store mode.
enum StoreMode: Sendable, Equatable {
    /// A file on the device — production mode.
    case onDevice
    /// A file at the given path — for migration tests.
    case file(URL)
    /// In memory — for tests and previews.
    case inMemory
}

/// Owner of the Core Data stack.
///
/// The store is local only: there's no paid Apple Developer account,
/// so CloudKit, the iCloud capability and shared databases were removed from the project.
/// Map exchange between devices comes in Phase 3 — locally,
/// via MultipeerConnectivity and files.
@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    /// Empty in-memory store — for SwiftUI previews.
    static let preview = PersistenceController(mode: .inMemory)

    /// Name of the `.xcdatamodeld`.
    static let modelName = "SoundMarks"

    let container: NSPersistentContainer
    private(set) var mode: StoreMode

    /// Error opening the store, if it didn't open.
    private(set) var loadFailure: AppError?

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(mode: StoreMode = .onDevice) {
        self.mode = mode

        if let model = Self.sharedModel {
            container = NSPersistentContainer(name: Self.modelName, managedObjectModel: model)
        } else {
            container = NSPersistentContainer(name: Self.modelName)
        }

        container.persistentStoreDescriptions = [Self.description(for: mode)]

        var failure: Error?
        container.loadPersistentStores { _, error in
            if let error { failure = error }
        }

        if let failure {
            Log.persistence.error("The store did not open: \(failure.localizedDescription, privacy: .public)")
            loadFailure = .persistenceUnavailable(reason: failure.localizedDescription)
        }

        configureViewContext()
    }

    // MARK: - Model

    /// The model is loaded once per process.
    ///
    /// Otherwise every container loads its own copy, and `+[Place entity]`
    /// can't pick an `NSEntityDescription` — Core Data complains
    /// «Multiple NSEntityDescriptions claim the NSManagedObject subclass».
    private static let sharedModel: NSManagedObjectModel? = {
        if let url = Bundle.main.url(forResource: modelName, withExtension: "momd"),
           let model = NSManagedObjectModel(contentsOf: url) {
            return model
        }
        Log.persistence.error("\(modelName, privacy: .public).momd not found in the bundle.")
        return NSManagedObjectModel.mergedModel(from: [Bundle.main])
    }()

    private static func description(for mode: StoreMode) -> NSPersistentStoreDescription {
        switch mode {
        case .inMemory:
            let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            description.type = NSInMemoryStoreType
            return description

        case .onDevice:
            // The file name predates the SoundMarks rename. It must stay as is:
            // a new name would open an empty store and hide all places already on the device.
            return fileDescription(url: storeURL(named: "MusicMap-local.sqlite"))
        case .file(let url):
            return fileDescription(url: url)
        }
    }

    private static func fileDescription(url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        // Lightweight migration: the model grows by phase, the user's data survives updates.
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        // Persistent history is required: the store was created with it, and without this option
        // Core Data opens it read-only — migration then fails.
        // In Phase 3 the same history is used to pick changes for syncing with friends.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        return description
    }

    private static func storeURL(named name: String) -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(name)
    }

    private func configureViewContext() {
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        viewContext.name = "viewContext"
        viewContext.undoManager = nil
    }

    // MARK: - Writing

    /// Saves `viewContext` if it has changes.
    func save() throws {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            Log.persistence.error("Save failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.persistenceUnavailable(reason: error.localizedDescription)
        }
    }

    /// Context for background work (scanning, import).
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }

    // MARK: - Personal map

    /// Returns the personal map, creating it on first launch.
    @discardableResult
    /// All my planets: the first one is the main one.
    func ownPlanets() throws -> [MemoryMap] {
        let main = try ensurePersonalMap()
        let request = MemoryMap.fetchRequest()
        request.predicate = NSPredicate(format: "kindRaw == %@", MemoryMapKind.own.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let all = (try? viewContext.fetch(request)) ?? []
        return [main] + all.filter { $0 != main }
    }

    /// Places without a map (from the very first versions) move to the main planet:
    /// now every planet shows only its own places.
    func adoptOrphanPlaces() {
        let request = Place.fetchRequest()
        request.predicate = NSPredicate(format: "map == nil")
        guard let orphans = try? viewContext.fetch(request), !orphans.isEmpty,
              let main = try? ensurePersonalMap() else { return }
        for place in orphans { place.map = main }
        try? save()
    }

    func ensurePersonalMap() throws -> MemoryMap {
        let request = MemoryMap.fetchRequest()
        request.predicate = NSPredicate(format: "kindRaw == %@", MemoryMapKind.own.rawValue)
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        if let existing = try? viewContext.fetch(request).first {
            return existing
        }

        let map = MemoryMap(context: viewContext)
        map.name = String(localized: "map.personal.name", defaultValue: "My map")
        map.kind = .own
        try save()
        return map
    }
}
