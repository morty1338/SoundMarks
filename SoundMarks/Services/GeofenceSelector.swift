import CoreLocation
import Foundation

/// Choosing geofences within the iOS limit: the system monitors no more than 20 regions at a time.
///
/// Pure logic — tested without Core Location.
enum GeofenceSelector {
    /// Places nearest to the point that have their geofence enabled.
    ///
    /// - Parameters:
    ///   - limit: how many regions to take. The system limit by default.
    ///   - now / cooldown: places that reminded recently go to the end of the queue
    ///     so they don't take slots near home.
    static func regions(for places: [PlaceSnapshot],
                        near coordinate: CLLocationCoordinate2D?,
                        limit: Int = GeofenceRegion.maximumSimultaneouslyMonitored,
                        radius: CLLocationDistance = GeofenceRegion.defaultRadius,
                        now: Date = Date(),
                        cooldown: TimeInterval = 0,
                        lastNotified: [UUID: Date] = [:]) -> [GeofenceRegion] {
        guard limit > 0 else { return [] }

        let eligible = places.filter(\.geofenceEnabled)
        guard !eligible.isEmpty else { return [] }

        let origin = coordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }

        let ranked = eligible.sorted { lhs, rhs in
            let leftCooling = isCooling(lhs.id, now: now, cooldown: cooldown, lastNotified: lastNotified)
            let rightCooling = isCooling(rhs.id, now: now, cooldown: cooldown, lastNotified: lastNotified)
            if leftCooling != rightCooling { return !leftCooling }

            guard let origin else { return lhs.createdAt > rhs.createdAt }
            let left = origin.distance(from: CLLocation(latitude: lhs.latitude, longitude: lhs.longitude))
            let right = origin.distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
            if left != right { return left < right }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return ranked.prefix(limit).map {
            GeofenceRegion(id: $0.id, latitude: $0.latitude, longitude: $0.longitude, radius: radius)
        }
    }

    /// Whether the cooldown has passed — whether this place may remind again.
    static func mayNotify(placeID: UUID,
                          now: Date = Date(),
                          cooldown: TimeInterval,
                          lastNotified: [UUID: Date]) -> Bool {
        !isCooling(placeID, now: now, cooldown: cooldown, lastNotified: lastNotified)
    }

    private static func isCooling(_ placeID: UUID,
                                  now: Date,
                                  cooldown: TimeInterval,
                                  lastNotified: [UUID: Date]) -> Bool {
        guard cooldown > 0, let last = lastNotified[placeID] else { return false }
        return now.timeIntervalSince(last) < cooldown
    }
}
