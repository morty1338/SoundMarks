import OSLog

/// Logging categories. Logs stay on the device, there's no analytics.
enum Log {
    private static let subsystem = "com.bibadev.musicmap"

    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let cloudKit = Logger(subsystem: subsystem, category: "cloudkit")
    static let music = Logger(subsystem: subsystem, category: "music")
    static let metadata = Logger(subsystem: subsystem, category: "metadata")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let photos = Logger(subsystem: subsystem, category: "photos")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
