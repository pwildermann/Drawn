import Foundation

struct DrawnTimer: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var duration: TimerDuration
    var doodleData: Data?
    var isRunning: Bool
    /// True once the timer has been started at least once (distinguishes paused from idle).
    var hasStarted: Bool
    /// Seconds remaining in the current countdown.
    var remainingSeconds: Int

    /// Elapsed fraction 0…1 (0 = just started, 1 = finished).
    var progress: Double {
        let total = duration.totalSeconds
        guard total > 0 else { return 0 }
        return Double(total - remainingSeconds) / Double(total)
    }

    var remainingDisplayText: String {
        let h = remainingSeconds / 3600
        let m = (remainingSeconds % 3600) / 60
        let s = remainingSeconds % 60
        // Format is fixed to match the original duration's precision
        if duration.hours > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        duration: TimerDuration,
        doodleData: Data? = nil,
        isRunning: Bool = false
    ) {
        self.id = id
        self.name = name
        self.duration = duration
        self.doodleData = doodleData
        self.isRunning = isRunning
        self.hasStarted = isRunning
        self.remainingSeconds = duration.totalSeconds
    }
}
