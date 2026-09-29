import Foundation

/// Local notifications: "on this day" and reminders when entering a geofence.
protocol NotificationService: Sendable {
    var isAuthorized: Bool { get async }

    func requestAuthorization() async throws -> Bool

    /// Completely reinstalls the "on this day" schedule.
    ///
    /// iOS keeps no more than `OnThisDayNotification.systemPendingLimit` scheduled
    /// local notifications, so the implementation schedules the nearest by date
    /// and recomputes the schedule at launch and on background refresh.
    func replaceOnThisDaySchedule(with notifications: [OnThisDayNotification]) async throws

    /// How many "on this day" notifications are actually scheduled.
    func scheduledOnThisDayCount() async -> Int

    /// An immediate reminder when entering a geofence, with a "Play" action.
    func presentGeofenceReminder(_ reminder: GeofenceReminder) async throws

    func cancelAllScheduled() async
}

/// Identifiers used to match a notification to a place on tap.
enum NotificationIdentifier {
    static let onThisDayPrefix = "onThisDay."
    static let geofencePrefix = "geofence."

    static let onThisDayCategory = "ON_THIS_DAY"
    static let geofenceCategory = "GEOFENCE_REMINDER"

    /// The "Play" action in the geofence push.
    static let playPreviewAction = "PLAY_PREVIEW"

    /// Key of `Place.id` in `userInfo`.
    static let placeIDsKey = "placeIDs"
}
