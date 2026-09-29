import CoreData
import Foundation

/// A trip: the recorded route plus places recovered from play timestamps.
@objc(Trip)
final class Trip: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var startedAt: Date?
    @NSManaged var endedAt: Date?

    @NSManaged var places: Set<Place>?
    @NSManaged var routePoints: Set<RoutePoint>?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        if id == nil { id = UUID() }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<Trip> {
        NSFetchRequest<Trip>(entityName: "Trip")
    }
}

extension Trip {
    /// The route in ascending time order.
    var orderedRoutePoints: [RoutePoint] {
        (routePoints ?? []).sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
    }

    var isActive: Bool { startedAt != nil && endedAt == nil }

    var dateInterval: DateInterval? {
        guard let startedAt else { return nil }
        return DateInterval(start: startedAt, end: endedAt ?? Date())
    }
}
