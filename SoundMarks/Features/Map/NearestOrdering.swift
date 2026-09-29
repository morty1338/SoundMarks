import CoreLocation
import Foundation

/// What strip orderings need: both the full snapshot and the lightweight index entry.
protocol PlaceOrderable {
    var id: UUID { get }
    var latitude: Double { get }
    var longitude: Double { get }
    var eventDate: EventDate? { get }
    var createdAt: Date { get }
    var country: String? { get }
}

extension PlaceSnapshot: PlaceOrderable {}
extension PlaceIndexEntry: PlaceOrderable {}

/// Record order for the "All" strip: from the nearest to the point outward.
enum NearestOrdering {
    static func sorted<Item: PlaceOrderable>(_ places: [Item], from origin: CLLocationCoordinate2D) -> [Item] {
        let anchor = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return places
            .map { ($0, anchor.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.id.uuidString < rhs.0.id.uuidString
            }
            .map(\.0)
    }
}
