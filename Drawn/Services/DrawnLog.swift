import OSLog
import os

enum DrawnLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "drawn"

    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let liveActivity = Logger(subsystem: subsystem, category: "liveActivity")
}
