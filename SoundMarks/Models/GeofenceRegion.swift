import CoreLocation
import Foundation

/// Geofence around a marked place.
struct GeofenceRegion: Hashable, Sendable, Identifiable {
    /// Matches `Place.id`.
    let id: UUID
    let latitude: Double
    let longitude: Double
    let radius: CLLocationDistance

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// iOS monitors no more than 20 regions at a time.
    static let maximumSimultaneouslyMonitored = 20
    static let defaultRadius: CLLocationDistance = 150

    init(id: UUID, latitude: Double, longitude: Double, radius: CLLocationDistance = Self.defaultRadius) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
    }
}
