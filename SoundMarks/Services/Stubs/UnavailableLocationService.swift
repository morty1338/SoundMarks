import CoreLocation
import Foundation

/// Stub until Core Location is implemented.
final class UnavailableLocationService: LocationService {
    var authorization: LocationAuthorization { get async { .notDetermined } }

    func requestWhenInUseAuthorization() async -> LocationAuthorization { .notDetermined }

    func requestAlwaysAuthorization() async -> LocationAuthorization { .notDetermined }

    func currentFix() async throws -> LocationFix {
        throw AppError.locationUnavailable
    }

    func placeInfo(for coordinate: CLLocationCoordinate2D) async -> PlaceInfo? { nil }

    func replaceMonitoredGeofences(with regions: [GeofenceRegion]) async throws {
        throw AppError.notImplemented(feature: String(localized: "feature.geofences", defaultValue: "Geofences"))
    }

    func stopMonitoringGeofences() async {}

    var geofenceEvents: AsyncStream<GeofenceEvent> { AsyncStream { $0.finish() } }

    func startTripTracking() async throws {
        throw AppError.notImplemented(feature: String(localized: "feature.trip", defaultValue: "Trip mode"))
    }

    func stopTripTracking() async {}

    var tripFixes: AsyncStream<LocationFix> { AsyncStream { $0.finish() } }
}
