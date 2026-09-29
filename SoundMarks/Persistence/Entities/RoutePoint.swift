import CoreData
import CoreLocation
import Foundation

/// A trip route point — a significant location change with a timestamp.
@objc(RoutePoint)
final class RoutePoint: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var timestamp: Date?

    @NSManaged var trip: Trip?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        if id == nil { id = UUID() }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<RoutePoint> {
        NSFetchRequest<RoutePoint>(entityName: "RoutePoint")
    }
}

extension RoutePoint {
    var coordinate: CLLocationCoordinate2D {
        get { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
        }
    }
}
