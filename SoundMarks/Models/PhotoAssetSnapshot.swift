import CoreLocation
import Foundation

/// Only the metadata of a library shot — the images themselves aren't loaded during scanning.
struct PhotoAssetSnapshot: Hashable, Sendable, Identifiable {
    /// `PHAsset.localIdentifier`.
    let id: String
    let kind: MediaKind
    let creationDate: Date
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var hasLocation: Bool { latitude != nil && longitude != nil }
}

/// Library access level. `limited` has to be supported on par with full.
enum PhotoAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case restricted
    case limited
    case authorized

    var allowsReading: Bool { self == .authorized || self == .limited }
}
