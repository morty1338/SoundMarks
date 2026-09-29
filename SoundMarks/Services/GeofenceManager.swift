import CoreData
import CoreLocation
import Foundation
import Observation

/// Keeps the set of 20 monitored places up to date and shows a reminder
/// when returning to a marked place.
@MainActor
@Observable
final class GeofenceManager {
    private(set) var monitoredCount = 0
    private(set) var lastError: String?

    @ObservationIgnored private let persistence: PersistenceController
    @ObservationIgnored private let location: any LocationService
    @ObservationIgnored private let notifications: any NotificationService
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var eventsTask: Task<Void, Never>?

    init(persistence: PersistenceController,
         location: any LocationService,
         notifications: any NotificationService,
         settings: AppSettings) {
        self.persistence = persistence
        self.location = location
        self.notifications = notifications
        self.settings = settings
    }

    deinit { eventsTask?.cancel() }

    /// Enables geofences: requests "always" access in context and starts monitoring.
    /// - Returns: `true` if monitoring started.
    @discardableResult
    func enable() async -> Bool {
        var authorization = await location.authorization
        if !authorization.allowsBackgroundUse {
            // "Always" access is asked only here — the rest of the app
            // is fine with "while using".
            authorization = await location.requestAlwaysAuthorization()
        }

        guard authorization.allowsBackgroundUse else {
            settings.geofencesEnabled = false
            lastError = AppError.permissionDenied(.locationAlways).errorDescription
            return false
        }

        if await !notifications.isAuthorized {
            _ = try? await notifications.requestAuthorization()
        }

        startObservingEvents()
        await refresh()
        return true
    }

    func disable() async {
        eventsTask?.cancel()
        eventsTask = nil
        await location.stopMonitoringGeofences()
        monitoredCount = 0
    }

    /// Recomputes the 20 nearest places. Called at launch, after
    /// adding a place and on a significant location change.
    func refresh() async {
        guard settings.geofencesEnabled else { return }

        let places = snapshots()
        let here = try? await location.currentFix()

        let regions = GeofenceSelector.regions(
            for: places,
            near: here?.coordinate,
            cooldown: cooldownInterval,
            lastNotified: lastNotifiedMap(for: places)
        )

        do {
            try await location.replaceMonitoredGeofences(with: regions)
            monitoredCount = regions.count
            lastError = nil
        } catch let error as AppError {
            lastError = error.errorDescription
            monitoredCount = 0
        } catch {
            lastError = error.localizedDescription
            monitoredCount = 0
        }
    }

    // MARK: - Events

    private func startObservingEvents() {
        guard eventsTask == nil else { return }
        let stream = location.geofenceEvents

        eventsTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { return }
                await self?.handle(event)
            }
        }
    }

    private func handle(_ event: GeofenceEvent) async {
        guard settings.geofencesEnabled else { return }
        guard let place = managedPlace(with: event.placeID), place.geofenceEnabled else { return }

        let lastNotified = place.lastGeofenceNotifiedAt.map { [event.placeID: $0] } ?? [:]
        guard GeofenceSelector.mayNotify(placeID: event.placeID,
                                         now: event.occurredAt,
                                         cooldown: cooldownInterval,
                                         lastNotified: lastNotified)
        else { return }

        guard let snapshot = place.snapshot(),
              let eventDate = snapshot.eventDate,
              let title = snapshot.trackTitle
        else { return }

        let reminder = GeofenceReminder(
            placeID: event.placeID,
            trackTitle: title,
            artist: snapshot.trackArtist ?? "",
            placeName: snapshot.placeName,
            eventDate: eventDate,
            previewURL: snapshot.previewURL
        )

        do {
            try await notifications.presentGeofenceReminder(reminder)
            place.lastGeofenceNotifiedAt = event.occurredAt
            try? persistence.save()
        } catch {
            Log.notifications.error("Reminder not shown: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Data

    private var cooldownInterval: TimeInterval {
        TimeInterval(settings.geofenceCooldownDays) * 24 * 3600
    }

    private func snapshots() -> [PlaceSnapshot] {
        let request = Place.fetchRequest(scope: .remindable)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            PlaceScope.remindable.predicate,
            NSPredicate(format: "geofenceEnabled == YES"),
        ])
        request.relationshipKeyPathsForPrefetching = ["track"]
        let context = persistence.viewContext
        return PlaceQueries.snapshots(of: (try? context.fetch(request)) ?? [], in: context)
    }

    /// When each place last reminded about itself — one dictionary query for all places.
    private func lastNotifiedMap(for places: [PlaceSnapshot]) -> [UUID: Date] {
        guard !places.isEmpty else { return [:] }
        let request = NSFetchRequest<NSDictionary>(entityName: "Place")
        request.resultType = .dictionaryResultType
        request.predicate = NSPredicate(format: "id IN %@ AND lastGeofenceNotifiedAt != nil", places.map(\.id))
        request.propertiesToFetch = ["id", "lastGeofenceNotifiedAt"]
        var result: [UUID: Date] = [:]
        for row in (try? persistence.viewContext.fetch(request)) ?? [] {
            guard let id = row["id"] as? UUID, let notified = row["lastGeofenceNotifiedAt"] as? Date else { continue }
            result[id] = notified
        }
        return result
    }

    private func managedPlace(with id: UUID) -> Place? {
        let request = Place.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? persistence.viewContext.fetch(request).first
    }
}
