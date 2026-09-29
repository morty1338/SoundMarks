import CoreLocation
import Foundation

/// A group of shots taken at about the same time and place.
struct PhotoCluster: Hashable, Sendable, Identifiable {
    let id: UUID
    let photos: [PhotoAssetSnapshot]
    let latitude: Double
    let longitude: Double
    /// From the first to the last shot of the group.
    let interval: DateInterval

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The middle of the shoot — track proximity is measured from it.
    var midpoint: Date {
        interval.start.addingTimeInterval(interval.duration / 2)
    }
}

/// A memory candidate: a group of photos plus tracks that played around that time.
struct MemoryCandidate: Hashable, Sendable, Identifiable {
    let id: UUID
    let cluster: PhotoCluster
    /// Matched tracks, from the closest in time to the farthest.
    /// The user can pick another one from this list.
    let trackOptions: [PlayRecord]
    /// Filled in by reverse geocoding in the feed, not during scanning.
    var placeInfo: PlaceInfo?

    /// For the card title: the city, otherwise a short name.
    var placeName: String? { placeInfo?.city ?? placeInfo?.shortName }
    var selectedTrackIndex: Int = 0

    var selectedTrack: PlayRecord? {
        trackOptions.indices.contains(selectedTrackIndex) ? trackOptions[selectedTrackIndex] : nil
    }

    var photos: [PhotoAssetSnapshot] { cluster.photos }
    var coordinate: CLLocationCoordinate2D { cluster.coordinate }

    /// The memory date — the day of the shoot.
    func eventDate(calendar: Calendar = .current) -> EventDate? {
        EventDate(date: cluster.interval.start, calendar: calendar)
    }
}
