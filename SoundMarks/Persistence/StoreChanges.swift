import CoreData
import Foundation

/// Subscription to store saves — only the relevant entities and at most once per run loop pass.
///
/// Previously screens re-read all places on any save: trip route points,
/// geofence marks and city backfilling also woke up the map and planet reloads.
/// Several saves in a row (import, sync) now result in a single reload.
@MainActor
final class StoreChanges {
    private let entityNames: Set<String>
    private let onChange: @MainActor () -> Void
    nonisolated(unsafe) private var observer: (any NSObjectProtocol)?
    private var isScheduled = false

    init(entities: Set<String>, onChange: @escaping @MainActor () -> Void) {
        entityNames = entities
        self.onChange = onChange
        observer = NotificationCenter.default.addObserver(
            forName: NSManagedObjectContext.didSaveObjectIDsNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let touched = Self.touchedEntities(in: notification)
            MainActor.assumeIsolated { self?.handle(touched) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func handle(_ touched: Set<String>) {
        guard !touched.isDisjoint(with: entityNames), !isScheduled else { return }
        isScheduled = true
        // The next main queue pass: by then `viewContext` has merged the background
        // context's changes, and a batch of saves in a row collapses into one reload.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isScheduled = false
                self.onChange()
            }
        }
    }

    /// Entity names from the notification — via `NSManagedObjectID`, which can be read from any thread.
    private nonisolated static func touchedEntities(in notification: Notification) -> Set<String> {
        var names = Set<String>()
        let keys: [NSManagedObjectContext.NotificationKey] = [.insertedObjectIDs, .updatedObjectIDs, .deletedObjectIDs]
        for key in keys {
            guard let ids = notification.userInfo?[key.rawValue] as? Set<NSManagedObjectID> else { continue }
            for id in ids {
                if let name = id.entity.name { names.insert(name) }
            }
        }
        return names
    }
}
