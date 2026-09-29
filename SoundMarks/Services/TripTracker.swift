import CoreData
import Foundation
import Observation

/// Travel mode: while a trip is running, the route is recorded locally.
/// What played is recovered after the trip from history timestamps.
@MainActor
@Observable
final class TripTracker {
    struct ActiveTrip: Equatable {
        let id: UUID
        let startedAt: Date
        var pointCount: Int
    }

    private(set) var active: ActiveTrip?

    @ObservationIgnored private let persistence: PersistenceController
    @ObservationIgnored private let location: @MainActor () -> any LocationService
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var lastSample: RouteSample?
    @ObservationIgnored private let options = TripMatcher.Options()

    init(persistence: PersistenceController, location: @escaping @MainActor () -> any LocationService) {
        self.persistence = persistence
        self.location = location
    }

    private var context: NSManagedObjectContext { persistence.viewContext }

    // MARK: - Trip

    /// After a relaunch (including a background one from a location change) recording continues.
    func resumeIfNeeded() {
        guard active == nil, let trip = activeTripEntity(), let id = trip.id, let startedAt = trip.startedAt else { return }
        let points = trip.orderedRoutePoints
        active = ActiveTrip(id: id, startedAt: startedAt, pointCount: points.count)
        lastSample = points.last.flatMap(Self.sample(from:))
        listen()
        Task { try? await location().startTripTracking() }
    }

    func start() async throws {
        guard active == nil else { return }
        try await location().startTripTracking()

        let trip = Trip(context: context)
        let now = Date()
        trip.startedAt = now
        trip.name = String(localized: "trip.defaultName",
                           defaultValue: "Trip \(now.formatted(.dateTime.day().month(.abbreviated)))")
        try persistence.save()

        guard let id = trip.id else { return }
        active = ActiveTrip(id: id, startedAt: now, pointCount: 0)
        lastSample = nil
        listen()
        Haptics.success()

        // The first point — right away, without waiting for a location change.
        if let fix = try? await location().currentFix() { record(fix) }
    }

    /// - Returns: identifier of the finished trip — for the summary screen.
    @discardableResult
    func finish() async -> UUID? {
        guard let active else { return nil }
        await location().stopTripTracking()
        listenTask?.cancel()
        listenTask = nil

        if let trip = trip(id: active.id) {
            trip.endedAt = Date()
            try? persistence.save()
        }
        self.active = nil
        lastSample = nil
        Haptics.success()
        return active.id
    }

    // MARK: - Trip history

    func finishedTrips() -> [Trip] {
        let request = Trip.fetchRequest()
        request.predicate = NSPredicate(format: "endedAt != nil")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func trip(id: UUID) -> Trip? {
        let request = Trip.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func route(of tripID: UUID) -> [RouteSample] {
        trip(id: tripID)?.orderedRoutePoints.compactMap(Self.sample(from:)) ?? []
    }

    /// Deletes the trip and its route. Saved places stay on the planet.
    func delete(tripID: UUID) throws {
        guard let trip = trip(id: tripID) else { return }
        context.delete(trip)
        try persistence.save()
    }

    // MARK: - Writing

    private func listen() {
        guard listenTask == nil else { return }
        let stream = location().tripFixes
        listenTask = Task { [weak self] in
            for await fix in stream {
                guard !Task.isCancelled else { return }
                self?.record(fix)
            }
        }
    }

    private func record(_ fix: LocationFix) {
        guard let active, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy < 2000,
              TripMatcher.shouldRecord(fix, after: lastSample, options: options),
              let trip = trip(id: active.id)
        else { return }

        let point = RoutePoint(context: context)
        point.latitude = fix.latitude
        point.longitude = fix.longitude
        point.timestamp = fix.timestamp
        point.trip = trip
        try? persistence.save()

        lastSample = RouteSample(latitude: fix.latitude, longitude: fix.longitude, timestamp: fix.timestamp)
        self.active?.pointCount += 1
    }

    private func activeTripEntity() -> Trip? {
        let request = Trip.fetchRequest()
        request.predicate = NSPredicate(format: "startedAt != nil AND endedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private static func sample(from point: RoutePoint) -> RouteSample? {
        guard let timestamp = point.timestamp else { return nil }
        return RouteSample(latitude: point.latitude, longitude: point.longitude, timestamp: timestamp)
    }
}
