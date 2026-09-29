import CoreLocation
import Foundation

/// Location, reverse geocoding, geofences and trip route recording.
protocol LocationService: AnyObject, Sendable {
    var authorization: LocationAuthorization { get async }

    /// Request for "while using" access — needed for "mark a place here".
    func requestWhenInUseAuthorization() async -> LocationAuthorization

    /// Request for "always" access — only in context, when enabling geofences or a trip.
    func requestAlwaysAuthorization() async -> LocationAuthorization

    /// Current location.
    func currentFix() async throws -> LocationFix

    /// Short name, city and country for a coordinate.
    func placeInfo(for coordinate: CLLocationCoordinate2D) async -> PlaceInfo?

    // MARK: - Geofences

    /// Replaces the set of monitored geofences.
    ///
    /// iOS monitors no more than `GeofenceRegion.maximumSimultaneouslyMonitored`
    /// regions at a time, so the caller passes the nearest places and recomputes
    /// the set on a significant location change.
    func replaceMonitoredGeofences(with regions: [GeofenceRegion]) async throws

    func stopMonitoringGeofences() async

    /// Stream of entries into monitored geofences.
    var geofenceEvents: AsyncStream<GeofenceEvent> { get }

    // MARK: - Travel mode

    /// Starts recording significant location changes.
    func startTripTracking() async throws

    func stopTripTracking() async

    /// Stream of route points.
    var tripFixes: AsyncStream<LocationFix> { get }
}
