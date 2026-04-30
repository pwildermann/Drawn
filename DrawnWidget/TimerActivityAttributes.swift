import ActivityKit
import Foundation

struct TimerActivityAttributes: ActivityAttributes {
    public typealias TimerStatus = ContentState

    public struct ContentState: Codable, Hashable {
        var name: String
        var endDate: Date
        var isPaused: Bool
        var remainingSeconds: Int
        var totalSeconds: Int
        var doodleImageData: Data? = nil
        var isRinging: Bool = false
        /// Monotonic per `activity.update` — helps ActivityKit apply each push as a distinct state.
        var contentPushEpoch: UInt64 = 0

        var progress: Double {
            guard totalSeconds > 0 else { return 0 }
            return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
        }
    }

    var timerID: String
    var doodleImageData: Data?

    init(timerID: String, doodleImageData: Data? = nil) {
        self.timerID = timerID
        self.doodleImageData = doodleImageData
    }
}
