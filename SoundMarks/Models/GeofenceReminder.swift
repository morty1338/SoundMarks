import Foundation

/// Push contents when returning to a marked place.
struct GeofenceReminder: Hashable, Sendable {
    let placeID: UUID
    let trackTitle: String
    let artist: String
    let placeName: String?
    /// The memory date — "2 years ago" is built from it.
    let eventDate: EventDate
    /// 30-second preview for the "Play" action.
    let previewURL: URL?
}
