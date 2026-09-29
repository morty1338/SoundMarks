import MapKit

/// Annotation of a place on the map.
final class PlaceAnnotation: NSObject, MKAnnotation {
    let place: PlaceSnapshot

    var coordinate: CLLocationCoordinate2D { place.coordinate }
    var title: String? { place.trackTitle }
    var subtitle: String? { place.displaySubtitle }

    init(place: PlaceSnapshot) {
        self.place = place
        super.init()
    }

    /// Annotations are compared by place — otherwise the map recreates pins on every refresh.
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PlaceAnnotation else { return false }
        return other.place == place
    }

    /// Hash by identifier: MapKit hashes annotations constantly, and hashing the full snapshot
    /// with strings and media on every call is expensive. Equal places share one identifier.
    override var hash: Int { place.id.hashValue }
}

extension MKClusterAnnotation {
    /// Places inside the stack, newest to oldest by event date.
    var places: [PlaceSnapshot] {
        memberAnnotations
            .compactMap { ($0 as? PlaceAnnotation)?.place }
            .sorted { lhs, rhs in
                switch (lhs.eventDate, rhs.eventDate) {
                case let (left?, right?): left > right
                case (nil, _?): false
                case (_?, nil): true
                case (nil, nil): lhs.createdAt > rhs.createdAt
                }
            }
    }

    /// All members sit at practically the same point — there's nothing to zoom into,
    /// such a stack has to be expanded as a list.
    var isTightlyPacked: Bool {
        let coordinates = memberAnnotations.map(\.coordinate)
        guard let first = coordinates.first else { return true }
        let origin = CLLocation(latitude: first.latitude, longitude: first.longitude)
        return coordinates.allSatisfy { coordinate in
            origin.distance(from: CLLocation(latitude: coordinate.latitude,
                                             longitude: coordinate.longitude)) < 25
        }
    }
}
