import Foundation
import UserNotifications

/// Local notifications via UserNotifications.
///
/// `UNUserNotificationCenter` isn't marked `Sendable`, but it is thread-safe by itself
/// and is used here only through async methods — hence `@unchecked`.
final class LocalNotificationService: NotificationService, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    var isAuthorized: Bool {
        get async {
            let settings = await center.notificationSettings()
            return settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        }
    }

    func requestAuthorization() async throws -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted { await registerCategories() }
            return granted
        } catch {
            Log.notifications.error("Permission request failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.permissionDenied(.notifications)
        }
    }

    // MARK: - "On this day"

    func replaceOnThisDaySchedule(with notifications: [OnThisDayNotification]) async throws {
        guard await isAuthorized else { throw AppError.permissionDenied(.notifications) }

        await cancelOnThisDay()

        // Stay within the iOS limit even if the caller passed more.
        let limited = notifications.prefix(OnThisDayNotification.systemPendingLimit)

        for notification in limited {
            let content = UNMutableNotificationContent()
            content.title = Self.title(for: notification)
            content.body = Self.body(for: notification)
            content.sound = .default
            content.categoryIdentifier = NotificationIdentifier.onThisDayCategory
            content.userInfo = [
                NotificationIdentifier.placeIDsKey: notification.placeIDs.map(\.uuidString),
            ]

            var components = DateComponents()
            components.month = notification.month
            components.day = notification.day
            components.hour = notification.hour
            components.minute = notification.minute

            let request = UNNotificationRequest(
                identifier: notification.id,
                content: content,
                // repeats with a month+day pair gives a yearly notification.
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )

            do {
                try await center.add(request)
            } catch {
                Log.notifications.error("Could not schedule \(notification.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        Log.notifications.info("Scheduled \"on this day\" notifications: \(limited.count, privacy: .public)")
    }

    func scheduledOnThisDayCount() async -> Int {
        await center.pendingNotificationRequests()
            .count { $0.identifier.hasPrefix(NotificationIdentifier.onThisDayPrefix) }
    }

    // MARK: - Geofences

    func presentGeofenceReminder(_ reminder: GeofenceReminder) async throws {
        guard await isAuthorized else { throw AppError.permissionDenied(.notifications) }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.geofence.title",
                               defaultValue: "You’ve been here before")
        content.body = String(localized: "notification.geofence.body",
                              defaultValue: "“\(reminder.trackTitle)” by \(reminder.artist) played here, \(reminder.eventDate.formatted())")
        content.sound = .default
        content.categoryIdentifier = NotificationIdentifier.geofenceCategory
        content.userInfo = [
            NotificationIdentifier.placeIDsKey: [reminder.placeID.uuidString],
        ]

        let request = UNNotificationRequest(
            identifier: "\(NotificationIdentifier.geofencePrefix)\(reminder.placeID.uuidString)",
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    func cancelAllScheduled() async {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Helpers

    private func cancelOnThisDay() async {
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(NotificationIdentifier.onThisDayPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func registerCategories() async {
        let play = UNNotificationAction(
            identifier: NotificationIdentifier.playPreviewAction,
            title: String(localized: "notification.action.play", defaultValue: "Play"),
            options: [.foreground]
        )
        let geofence = UNNotificationCategory(
            identifier: NotificationIdentifier.geofenceCategory,
            actions: [play],
            intentIdentifiers: []
        )
        let onThisDay = UNNotificationCategory(
            identifier: NotificationIdentifier.onThisDayCategory,
            actions: [],
            intentIdentifiers: []
        )
        center.setNotificationCategories([geofence, onThisDay])
    }

    private static func title(for notification: OnThisDayNotification) -> String {
        String(localized: "notification.onThisDay.title", defaultValue: "On this day")
    }

    private static func body(for notification: OnThisDayNotification) -> String {
        guard let first = notification.entries.first else { return "" }

        if notification.entries.count == 1 {
            let track = [first.trackTitle, first.artist].compactMap { $0 }.joined(separator: " — ")
            let where_ = first.placeName ?? String(localized: "notification.onThisDay.somewhere",
                                                   defaultValue: "somewhere on the map")
            return String(localized: "notification.onThisDay.single",
                          defaultValue: "\(first.year), \(where_): you were listening to \(track)")
        }

        let places = notification.entries
            .compactMap { $0.placeName ?? $0.trackTitle }
            .prefix(3)
            .joined(separator: ", ")
        return String(localized: "notification.onThisDay.multiple",
                      defaultValue: "\(notification.entries.count) memories: \(places)")
    }
}
