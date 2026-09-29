import CoreLocation
import Foundation

/// A route point without Core Data — for pure computations and tests.
struct RouteSample: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A trip stop: where tracks played and which photos were taken nearby.
struct TripStop: Hashable, Sendable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    /// This stop's plays without repeats, by time. The first one is the main one.
    let plays: [PlayRecord]
    let photos: [PhotoAssetSnapshot]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var startedAt: Date { plays.first?.playedAt ?? .distantPast }
}

/// Recovering records along the way: a track's position is taken from its timestamp.
///
/// During a trip only route points are recorded; what played is taken
/// from the listening history after the trip. Geotagged photos close in time
/// are more precise than the route, so they take priority.
enum TripMatcher {
    struct Options: Sendable {
        /// A new point is recorded if we moved farther than this distance…
        var minimumRecordDistance: CLLocationDistance = 150
        /// …or this much time has passed.
        var minimumRecordInterval: TimeInterval = 15 * 60
        /// Tracks closer than this distance and gap form one stop.
        var stopMergeDistance: CLLocationDistance = 1000
        var stopMergeGap: TimeInterval = 30 * 60
        /// Window in which a photo belongs to a track.
        var photoWindow: TimeInterval = 30 * 60
    }

    /// Whether a new route point should be recorded.
    static func shouldRecord(_ fix: LocationFix, after last: RouteSample?, options: Options = Options()) -> Bool {
        guard let last else { return true }
        guard fix.timestamp > last.timestamp else { return false }
        let distance = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
            .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
        return distance >= options.minimumRecordDistance
            || fix.timestamp.timeIntervalSince(last.timestamp) >= options.minimumRecordInterval
    }

    /// Where we were at `date`: linear interpolation between neighboring points.
    /// Before the first and after the last point — the outermost route point.
    static func position(at date: Date, on route: [RouteSample]) -> CLLocationCoordinate2D? {
        let sorted = route.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        if date <= first.timestamp { return first.coordinate }
        if date >= last.timestamp { return last.coordinate }

        for (before, after) in zip(sorted, sorted.dropFirst()) where date <= after.timestamp {
            let span = after.timestamp.timeIntervalSince(before.timestamp)
            guard span > 0 else { return after.coordinate }
            let t = date.timeIntervalSince(before.timestamp) / span
            return CLLocationCoordinate2D(
                latitude: before.latitude + (after.latitude - before.latitude) * t,
                longitude: before.longitude + (after.longitude - before.longitude) * t
            )
        }
        return last.coordinate
    }

    /// Trip stops from plays, the route and photos.
    static func stops(route: [RouteSample],
                      plays: [PlayRecord],
                      photos: [PhotoAssetSnapshot],
                      options: Options = Options()) -> [TripStop] {
        let meaningful = plays.filter(\.isMeaningfulPlayback).sorted { $0.playedAt < $1.playedAt }
        let located = photos.filter(\.hasLocation).sorted { $0.creationDate < $1.creationDate }

        // 1. A coordinate for every track.
        var positioned: [(play: PlayRecord, coordinate: CLLocationCoordinate2D)] = []
        for play in meaningful {
            if let photo = closestPhoto(to: play.playedAt, in: located, window: options.photoWindow),
               let coordinate = photo.coordinate {
                positioned.append((play, coordinate))
            } else if let coordinate = position(at: play.playedAt, on: route) {
                positioned.append((play, coordinate))
            }
        }

        // 2. Tracks close in time and place form one stop.
        var groups: [[(play: PlayRecord, coordinate: CLLocationCoordinate2D)]] = []
        for item in positioned {
            if let previous = groups.last?.last,
               item.play.playedAt.timeIntervalSince(previous.play.playedAt) <= options.stopMergeGap,
               distance(previous.coordinate, item.coordinate) <= options.stopMergeDistance {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
            }
        }

        // 3. A stop: the group center, tracks without repeats, photos in the window.
        return groups.compactMap { group in
            guard let first = group.first, let last = group.last else { return nil }
            let latitude = group.map(\.coordinate.latitude).reduce(0, +) / Double(group.count)
            let longitude = group.map(\.coordinate.longitude).reduce(0, +) / Double(group.count)

            var seen: Set<String> = []
            let unique = group.map(\.play).filter { seen.insert($0.trackKey).inserted }

            let from = first.play.playedAt.addingTimeInterval(-options.photoWindow)
            let to = last.play.playedAt.addingTimeInterval(options.photoWindow)
            let stopPhotos = photos.filter { $0.creationDate >= from && $0.creationDate <= to }
                .sorted { $0.creationDate < $1.creationDate }

            return TripStop(id: UUID(), latitude: latitude, longitude: longitude,
                            plays: unique, photos: stopPhotos)
        }
    }

    private static func closestPhoto(to date: Date, in photos: [PhotoAssetSnapshot],
                                     window: TimeInterval) -> PhotoAssetSnapshot? {
        photos
            .filter { abs($0.creationDate.timeIntervalSince(date)) <= window }
            .min { abs($0.creationDate.timeIntervalSince(date)) < abs($1.creationDate.timeIntervalSince(date)) }
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
