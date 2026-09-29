import Foundation
import Observation
import UserNotifications

/// Receives a notification tap and tells the map which place to open.
@MainActor
@Observable
final class NotificationRouter: NSObject {
    /// The place that should be shown. The map opens it and calls `clear()`.
    private(set) var requestedPlaceID: UUID?

    func clear() { requestedPlaceID = nil }

    fileprivate func request(placeID: UUID) { requestedPlaceID = placeID }
}

extension NotificationRouter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let raw = userInfo[NotificationIdentifier.placeIDsKey] as? [String],
              let first = raw.first,
              let placeID = UUID(uuidString: first)
        else { return }

        await request(placeID: placeID)
    }

    /// Show the notification even when the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
