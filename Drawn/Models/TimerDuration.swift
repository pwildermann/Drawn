import Foundation

struct TimerDuration: Codable, Hashable {
    var hours: Int
    var minutes: Int
    var seconds: Int

    var totalSeconds: Int {
        (hours * 3600) + (minutes * 60) + seconds
    }

    var displayText: String {
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    static let zero = TimerDuration(hours: 0, minutes: 0, seconds: 0)
}
