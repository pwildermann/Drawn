import Foundation
import DrawnTimerEngine

struct TimerPersistenceService {
    static let shared = TimerPersistenceService()
    private init() {}

    private struct PersistedTimersEnvelope: Codable {
        var savedAt: Date
        var timers: [DrawnTimer]
    }

    private var saveURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("timers.json")
    }

    func save(_ timers: [DrawnTimer]) {
        let envelope = PersistedTimersEnvelope(savedAt: Date(), timers: timers)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    func load() -> [DrawnTimer] {
        guard let data = try? Data(contentsOf: saveURL) else { return [] }

        // Backward compatibility: older builds persisted `[DrawnTimer]` directly.
        let decoded: (timers: [DrawnTimer], savedAt: Date)?
        if let envelope = try? JSONDecoder().decode(PersistedTimersEnvelope.self, from: data) {
            decoded = (envelope.timers, envelope.savedAt)
        } else if let timers = try? JSONDecoder().decode([DrawnTimer].self, from: data) {
            decoded = (timers, Date())
        } else {
            decoded = nil
        }
        guard let decoded else { return [] }
        var timers = decoded.timers
        let elapsed = max(0, Int(decoded.savedAt.timeIntervalSinceNow * -1))

        // Preserve running state across cold launch when there is still time left.
        // This keeps in-app state aligned with Live Activity countdown (`endDate`) instead of force-pausing.
        for i in timers.indices where timers[i].isRunning {
            let adjustedRemaining = RunningTimerDeadlineMath.remainingAfterElapsed(
                savedRemainingSeconds: timers[i].remainingSeconds,
                elapsedSeconds: elapsed
            )
            timers[i].remainingSeconds = adjustedRemaining
            if adjustedRemaining > 0 {
                timers[i].isRunning = true
                timers[i].hasStarted = true
            } else {
                timers[i].isRunning = false
            }
        }
        return timers
    }
}
