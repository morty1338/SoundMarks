import CoreLocation
import Foundation

/// Immutable place snapshot for UI and background work.
///
/// The map, timeline and notification scheduler work with snapshots rather than
/// `NSManagedObject`: values freely cross actor boundaries, and with
/// 1000+ places redrawing doesn't poke Core Data.
struct PlaceSnapshot: Hashable, Sendable, Identifiable {
    struct Media: Hashable, Sendable, Identifiable {
        let id: UUID
        let kind: MediaKind
        let localIdentifier: String?
        let hasEmbeddedData: Bool
        let takenAt: Date?
    }

    let id: UUID
    let latitude: Double
    let longitude: Double
    let placeName: String?
    let city: String?
    let country: String?
    let note: String?
    let createdAt: Date
    let eventDate: EventDate?
    let pinStyleOverride: PinStyle?
    let geofenceEnabled: Bool

    let trackTitle: String?
    let trackArtist: String?
    let artworkURL: URL?
    let previewURL: URL?

    let media: [Media]
    /// This place's record skin; `nil` — the default skin.
    var skinID: String? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func pinStyle(fallback: PinStyle) -> PinStyle { pinStyleOverride ?? fallback }

    /// The date by which the place is placed on the timeline.
    func timelineDate(calendar: Calendar = .current) -> Date? {
        eventDate?.sortDate(calendar: calendar)
    }

    var displayTitle: String {
        trackTitle ?? String(localized: "place.untitledTrack", defaultValue: "No track")
    }

    var displaySubtitle: String {
        [trackArtist, placeName].compactMap { $0 }.joined(separator: " · ")
    }

    /// Short name for the card and titles: a POI or neighborhood, otherwise the city.
    var shortPlaceName: String? { placeName ?? city }

    /// Date in "dd.mm.yyyy" format respecting precision: "2016", "08.2016", "14.08.2016".
    var compactDate: String? {
        guard let eventDate else { return nil }
        switch eventDate.precision {
        case .year:
            return String(eventDate.year)
        case .month:
            return String(format: "%02d.%d", eventDate.month ?? 1, eventDate.year)
        case .day:
            return String(format: "%02d.%02d.%d", eventDate.day ?? 1, eventDate.month ?? 1, eventDate.year)
        }
    }
}

extension Place {
    /// Snapshot for the UI. `nil` if the object has no identifier —
    /// that shouldn't happen, but crashing over it isn't allowed.
    ///
    /// For a batch of places — `PlaceQueries.snapshots(of:in:)`: the media of all places in one query.
    func snapshot() -> PlaceSnapshot? {
        guard let context = managedObjectContext else { return snapshot(media: inMemoryMedia) }
        return PlaceQueries.snapshots(of: [self], in: context).first
    }

    /// Snapshot with media that are already collected.
    func snapshot(media: [PlaceSnapshot.Media]) -> PlaceSnapshot? {
        guard let id else {
            Log.persistence.error("Skipped a place without an identifier.")
            return nil
        }
        return PlaceSnapshot(
            id: id,
            latitude: latitude,
            longitude: longitude,
            placeName: placeName,
            city: city,
            country: country,
            note: note,
            createdAt: createdAt ?? Date(),
            eventDate: eventDate,
            pinStyleOverride: pinStyleOverride,
            geofenceEnabled: geofenceEnabled,
            trackTitle: track?.title,
            trackArtist: track?.artist,
            artworkURL: track?.artworkLink,
            previewURL: track?.previewLink,
            media: media,
            skinID: skinID
        )
    }

    /// Media from in-memory objects — for unsaved edits the query can't see.
    var inMemoryMedia: [PlaceSnapshot.Media] {
        orderedMedia.compactMap { item in
            item.id.map {
                PlaceSnapshot.Media(id: $0,
                                    kind: item.kind,
                                    localIdentifier: item.localIdentifier,
                                    hasEmbeddedData: item.imageData != nil,
                                    takenAt: item.takenAt)
            }
        }
    }
}
