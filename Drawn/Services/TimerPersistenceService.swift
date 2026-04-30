import Foundation

struct TimerPersistenceService {
    static let shared = TimerPersistenceService()
    private init() {}

    private var saveURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("timers.json")
    }

    func save(_ timers: [DrawnTimer]) {
        guard let data = try? JSONEncoder().encode(timers) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    func load() -> [DrawnTimer] {
        guard
            let data = try? Data(contentsOf: saveURL),
            var timers = try? JSONDecoder().decode([DrawnTimer].self, from: data)
        else { return [] }
        // Timers can't be actively running after a cold launch — mark them as paused.
        for i in timers.indices where timers[i].isRunning {
            timers[i].isRunning = false
        }
        return timers
    }
}
