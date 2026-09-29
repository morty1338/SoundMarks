import CoreLocation
import Foundation

/// Core Location: current location and reverse geocoding.
///
/// Geofences via `CLMonitor`, the trip route via significant location changes:
/// they barely use battery and wake the app in the background.
@MainActor
final class CoreLocationService: NSObject, LocationService {
    /// Name of the `CLMonitor` condition set; the system keeps it between launches.
    /// Predates the SoundMarks rename: the system keeps monitors by name, so a new name
    /// would leave the old one running alongside.
    private static let monitorName = "MusicMapGeofences"

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    /// Waiting for the answer to a permission request. Remembers the status at request time
    /// so it doesn't finish on a callback that merely repeats the current status.
    private struct AuthorizationWaiter {
        let initialStatus: CLAuthorizationStatus
        let continuation: CheckedContinuation<LocationAuthorization, Never>
    }

    private var authorizationWaiters: [AuthorizationWaiter] = []
    private var fixWaiters: [CheckedContinuation<LocationFix, any Error>] = []

    nonisolated private let geofenceStream: AsyncStream<GeofenceEvent>
    nonisolated private let geofenceContinuation: AsyncStream<GeofenceEvent>.Continuation
    nonisolated private let tripStream: AsyncStream<LocationFix>
    nonisolated private let tripContinuation: AsyncStream<LocationFix>.Continuation

    private var isTrackingTrip = false
    /// Keeps "while using" access alive in the background if "always" was not granted.
    private var backgroundSession: CLBackgroundActivitySession?

    private var monitor: CLMonitor?
    private var monitorTask: Task<Void, Never>?

    override init() {
        (geofenceStream, geofenceContinuation) = AsyncStream.makeStream(of: GeofenceEvent.self)
        (tripStream, tripContinuation) = AsyncStream.makeStream(of: LocationFix.self)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    deinit {
        monitorTask?.cancel()
        geofenceContinuation.finish()
        tripContinuation.finish()
    }

    // MARK: - Permissions

    var authorization: LocationAuthorization {
        Self.map(manager.authorizationStatus)
    }

    func requestWhenInUseAuthorization() async -> LocationAuthorization {
        guard manager.authorizationStatus == .notDetermined else { return authorization }
        return await requestAuthorization { $0.requestWhenInUseAuthorization() }
    }

    /// "Always" access is requested only in context — when enabling geofences.
    func requestAlwaysAuthorization() async -> LocationAuthorization {
        guard manager.authorizationStatus != .authorizedAlways else { return .always }
        return await requestAuthorization { $0.requestAlwaysAuthorization() }
    }

    private func requestAuthorization(
        _ ask: @escaping (CLLocationManager) -> Void
    ) async -> LocationAuthorization {
        let initialStatus = manager.authorizationStatus

        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(
                AuthorizationWaiter(initialStatus: initialStatus, continuation: continuation)
            )
            ask(manager)

            // The system can be asked but not forced to show the dialog:
            // the upgrade to "always" is offered only once. So that the calling code
            // doesn't wait forever, we answer with the current status after a few seconds.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.resolveAuthorizationWaiters(force: true)
            }
        }
    }

    // MARK: - Current position

    func currentFix() async throws -> LocationFix {
        if manager.authorizationStatus == .notDetermined {
            _ = await requestWhenInUseAuthorization()
        }
        guard authorization.allowsForegroundUse else {
            throw AppError.permissionDenied(.locationWhenInUse)
        }

        // A fresh system cache saves waiting for a new fix.
        if let cached = manager.location, Date().timeIntervalSince(cached.timestamp) < 30 {
            return LocationFix(location: cached)
        }

        return try await withCheckedThrowingContinuation { continuation in
            fixWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    func placeInfo(for coordinate: CLLocationCoordinate2D) async -> PlaceInfo? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            guard let placemark = try await geocoder.reverseGeocodeLocation(location).first else { return nil }
            return Self.info(for: placemark)
        } catch {
            // Without a name the place is still saved — we don't treat this as an error for the user.
            Log.location.debug("Reverse geocoding failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Geofences

    /// Replaces the set of monitored regions.
    ///
    /// The caller has already trimmed the list to the 20 nearest — here we only handle
    /// the difference between what is monitored and what is needed.
    func replaceMonitoredGeofences(with regions: [GeofenceRegion]) async throws {
        guard authorization.allowsBackgroundUse else {
            throw AppError.permissionDenied(.locationAlways)
        }
        guard regions.count <= GeofenceRegion.maximumSimultaneouslyMonitored else {
            throw AppError.other(message: String(
                localized: "error.tooManyGeofences",
                defaultValue: "iOS monitors at most \(GeofenceRegion.maximumSimultaneouslyMonitored) places at once."
            ))
        }

        let monitor = await activeMonitor()
        let wanted = Dictionary(regions.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        let existing = Set(await monitor.identifiers)

        for identifier in existing.subtracting(wanted.keys) {
            await monitor.remove(identifier)
        }

        for (identifier, region) in wanted where !existing.contains(identifier) {
            await monitor.add(
                CLMonitor.CircularGeographicCondition(center: region.coordinate, radius: region.radius),
                identifier: identifier,
                assuming: .unsatisfied
            )
        }

        // Recomputing the set is tied to significant location changes.
        manager.startMonitoringSignificantLocationChanges()
        Log.location.info("Monitoring geofences: \(regions.count, privacy: .public)")
    }

    func stopMonitoringGeofences() async {
        monitorTask?.cancel()
        monitorTask = nil

        if let monitor {
            for identifier in await monitor.identifiers {
                await monitor.remove(identifier)
            }
        }
        monitor = nil
        manager.stopMonitoringSignificantLocationChanges()
    }

    nonisolated var geofenceEvents: AsyncStream<GeofenceEvent> { geofenceStream }

    /// Starts `CLMonitor` and subscribes to its events once.
    private func activeMonitor() async -> CLMonitor {
        if let monitor { return monitor }

        let created = await CLMonitor(Self.monitorName)
        monitor = created

        monitorTask = Task { [weak self] in
            do {
                for try await event in await created.events {
                    guard !Task.isCancelled else { return }
                    // Only entering the zone matters.
                    guard event.state == .satisfied,
                          let placeID = UUID(uuidString: event.identifier)
                    else { continue }
                    self?.emitGeofenceEvent(placeID: placeID, at: event.date)
                }
            } catch {
                Log.location.error("Geofence event stream interrupted: \(error.localizedDescription, privacy: .public)")
            }
        }
        return created
    }

    private func emitGeofenceEvent(placeID: UUID, at date: Date) {
        geofenceContinuation.yield(GeofenceEvent(placeID: placeID, occurredAt: date))
    }

    // MARK: - Travel mode

    /// Significant location changes (roughly every 500 m): a route without wasting battery.
    /// "Always" is asked in context — right now, when a trip starts.
    func startTripTracking() async throws {
        var status = await requestWhenInUseAuthorization()
        guard status.allowsForegroundUse else { throw AppError.permissionDenied(.locationWhenInUse) }
        if status != .always {
            status = await requestAlwaysAuthorization()
        }

        guard !isTrackingTrip else { return }
        isTrackingTrip = true
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        if status != .always {
            // Without "always" background recording relies on an active session with an indicator.
            backgroundSession = CLBackgroundActivitySession()
        }
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopTripTracking() async {
        guard isTrackingTrip else { return }
        isTrackingTrip = false
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    private func emitTripFixes(_ fixes: [LocationFix]) {
        guard isTrackingTrip else { return }
        for fix in fixes { tripContinuation.yield(fix) }
    }

    nonisolated var tripFixes: AsyncStream<LocationFix> { tripStream }

    // MARK: - Helpers

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        @unknown default: .notDetermined
        }
    }

    /// Short name: a landmark, then the neighborhood, then the street without a number, then the city.
    static func info(for placemark: CLPlacemark) -> PlaceInfo {
        let candidates = [
            placemark.areasOfInterest?.first,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
        ]
        let shortName = candidates.lazy.compactMap { $0 }.first { !$0.isEmpty }
        return PlaceInfo(shortName: shortName,
                         city: placemark.locality ?? placemark.administrativeArea,
                         country: placemark.country)
    }

    private func resolveAuthorizationWaiters(force: Bool = false) {
        let status = manager.authorizationStatus
        let result = authorization

        var pending: [AuthorizationWaiter] = []
        for waiter in authorizationWaiters {
            let answered = status != waiter.initialStatus && status != .notDetermined
            if force || answered {
                waiter.continuation.resume(returning: result)
            } else {
                pending.append(waiter)
            }
        }
        authorizationWaiters = pending
    }

    private func resolveFixWaiters(with result: Result<LocationFix, any Error>) {
        let waiters = fixWaiters
        fixWaiters.removeAll()
        for waiter in waiters { waiter.resume(with: result) }
    }
}

// MARK: - CLLocationManagerDelegate

extension CoreLocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.resolveAuthorizationWaiters() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map(LocationFix.init(location:))
        guard let fix = fixes.last else { return }
        Task { @MainActor in
            self.resolveFixWaiters(with: .success(fix))
            self.emitTripFixes(fixes)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Log.location.error("Could not get the location: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in self.resolveFixWaiters(with: .failure(AppError.locationUnavailable)) }
    }
}
