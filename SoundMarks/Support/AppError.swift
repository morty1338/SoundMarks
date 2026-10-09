import Foundation

/// App-level errors. They always have a human-readable description —
/// the UI shows `errorDescription`, never a "raw" NSError.
enum AppError: LocalizedError, Equatable {
    /// The feature is planned for a later phase.
    case notImplemented(feature: String)
    /// The local store could not be opened.
    case persistenceUnavailable(reason: String)
    /// No network access or the service is unavailable.
    case networkUnavailable
    /// The user didn't grant permission.
    case permissionDenied(PermissionKind)
    /// Could not determine the current location.
    case locationUnavailable
    /// The music source isn't connected.
    case musicSourceNotConnected(MusicSourceKind)
    /// The source couldn't determine what is playing now.
    case nothingPlaying
    /// Invalid event date (the year is required).
    case invalidEventDate
    /// Could not parse the import file.
    case importFileUnreadable(reason: String)
    /// Last.fm isn't configured by the developer: no API key in the build.
    case lastFmNotConfigured
    /// Anything else, with a text that is already prepared.
    case other(message: String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let feature):
            String(localized: "error.notImplemented",
                   defaultValue: "“\(feature)” isn’t available yet.")
        case .persistenceUnavailable:
            String(localized: "error.persistenceUnavailable",
                   defaultValue: "Couldn’t open the local memories database.")
        case .networkUnavailable:
            String(localized: "error.networkUnavailable",
                   defaultValue: "No internet connection.")
        case .permissionDenied(let kind):
            String(localized: "error.permissionDenied",
                   defaultValue: "No access to \(kind.localizedName).")
        case .locationUnavailable:
            String(localized: "error.locationUnavailable",
                   defaultValue: "Couldn’t determine your location.")
        case .musicSourceNotConnected(let kind):
            String(localized: "error.musicSourceNotConnected",
                   defaultValue: "\(kind.localizedName) isn’t connected.")
        case .nothingPlaying:
            String(localized: "error.nothingPlaying",
                   defaultValue: "Couldn’t tell what’s playing right now.")
        case .invalidEventDate:
            String(localized: "error.invalidEventDate",
                   defaultValue: "Enter at least the year.")
        case .importFileUnreadable:
            String(localized: "error.importFileUnreadable",
                   defaultValue: "Couldn’t read the streaming history file.")
        case .lastFmNotConfigured:
            String(localized: "error.lastFmNotConfigured",
                   defaultValue: "Last.fm isn’t wired up in this build yet.")
        case .other(let message):
            message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            String(localized: "error.permissionDenied.recovery",
                   defaultValue: "You can grant permission in Settings.")
        case .networkUnavailable:
            String(localized: "error.networkUnavailable.recovery",
                   defaultValue: "Check your connection and try again.")
        case .musicSourceNotConnected:
            String(localized: "error.musicSourceNotConnected.recovery",
                   defaultValue: "Connect the source in Settings or pick a track manually.")
        case .nothingPlaying:
            String(localized: "error.nothingPlaying.recovery",
                   defaultValue: "Search for the track manually.")
        case .importFileUnreadable:
            String(localized: "error.importFileUnreadable.recovery",
                   defaultValue: "Pick the ZIP from your Spotify data export or a StreamingHistory_music / Streaming_History_Audio JSON file from it.")
        case .lastFmNotConfigured:
            String(localized: "error.lastFmNotConfigured.recovery",
                   defaultValue: "Import your Spotify history — it works without a key.")
        case .notImplemented, .persistenceUnavailable, .locationUnavailable, .invalidEventDate, .other:
            nil
        }
    }

    /// Technical reason for logs — not for the user.
    var diagnosticDetail: String? {
        switch self {
        case .persistenceUnavailable(let reason): reason
        case .importFileUnreadable(let reason): reason
        default: nil
        }
    }
}

/// Permissions the app requests.
enum PermissionKind: String, Sendable, CaseIterable {
    case photoLibrary
    case locationWhenInUse
    case locationAlways
    case notifications

    var localizedName: String {
        switch self {
        case .photoLibrary:
            String(localized: "permission.photoLibrary", defaultValue: "photos")
        case .locationWhenInUse:
            String(localized: "permission.locationWhenInUse", defaultValue: "location")
        case .locationAlways:
            String(localized: "permission.locationAlways", defaultValue: "location in the background")
        case .notifications:
            String(localized: "permission.notifications", defaultValue: "notifications")
        }
    }
}
