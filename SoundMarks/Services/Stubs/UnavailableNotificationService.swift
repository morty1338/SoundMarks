import Foundation

/// Stub until UserNotifications is implemented.
final class UnavailableNotificationService: NotificationService {
    var isAuthorized: Bool { get async { false } }

    func requestAuthorization() async throws -> Bool { false }

    func replaceOnThisDaySchedule(with notifications: [OnThisDayNotification]) async throws {
        throw AppError.notImplemented(feature: String(localized: "feature.onThisDay", defaultValue: "“On this day” notifications"))
    }

    func scheduledOnThisDayCount() async -> Int { 0 }

    func presentGeofenceReminder(_ reminder: GeofenceReminder) async throws {
        throw AppError.notImplemented(feature: String(localized: "feature.geofences", defaultValue: "Geofences"))
    }

    func cancelAllScheduled() async {}
}
