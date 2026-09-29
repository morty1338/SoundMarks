import CoreLocation
import Foundation

/// A location snapshot. A separate type instead of `CLLocation` so the value
/// can freely cross actor boundaries.
struct LocationFix: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: CLLocationAccuracy
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double, longitude: Double, horizontalAccuracy: CLLocationAccuracy, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }

    init(location: CLLocation) {
        self.init(latitude: location.coordinate.latitude,
                  longitude: location.coordinate.longitude,
                  horizontalAccuracy: location.horizontalAccuracy,
                  timestamp: location.timestamp)
    }
}

/// Location access status in the app's terms.
enum LocationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case restricted
    case whenInUse
    case always

    /// Enough for "mark a place here".
    var allowsForegroundUse: Bool { self == .whenInUse || self == .always }
    /// Enough for geofences and travel mode.
    var allowsBackgroundUse: Bool { self == .always }
}

/// Entering a marked place's geofence.
struct GeofenceEvent: Hashable, Sendable {
    /// `Place.id`.
    let placeID: UUID
    let occurredAt: Date
}

/// What is known about a point after reverse geocoding.
struct PlaceInfo: Hashable, Sendable {
    /// A POI or a neighborhood — something a person recognizes. Never a full address with a house number.
    let shortName: String?
    let city: String?
    let country: String?
}
