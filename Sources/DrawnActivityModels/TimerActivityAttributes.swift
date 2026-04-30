#if os(iOS)
import ActivityKit
import Foundation

/// Live Activity payload — **must** come from a **single Swift module** linked by both the app and
/// `DrawnWidgetExtension`. Compiling a copy per target produces two distinct `ActivityAttributes`
/// types; ActivityKit then fails to route `Activity.update` → widget UI (stale / “paused” island).
public struct TimerActivityAttributes: ActivityAttributes {
    public typealias TimerStatus = ContentState

    public struct ContentState: Codable, Hashable, Sendable {
        public var name: String
        public var endDate: Date
        public var isPaused: Bool
        public var remainingSeconds: Int
        public var totalSeconds: Int
        public var doodleImageData: Data?
        public var isRinging: Bool
        public var contentPushEpoch: UInt64

        public var progress: Double {
            guard totalSeconds > 0 else { return 0 }
            return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
        }

        public init(
            name: String,
            endDate: Date,
            isPaused: Bool,
            remainingSeconds: Int,
            totalSeconds: Int,
            doodleImageData: Data? = nil,
            isRinging: Bool = false,
            contentPushEpoch: UInt64 = 0
        ) {
            self.name = name
            self.endDate = endDate
            self.isPaused = isPaused
            self.remainingSeconds = remainingSeconds
            self.totalSeconds = totalSeconds
            self.doodleImageData = doodleImageData
            self.isRinging = isRinging
            self.contentPushEpoch = contentPushEpoch
        }
    }

    public var timerID: String
    public var doodleImageData: Data?

    public init(timerID: String, doodleImageData: Data? = nil) {
        self.timerID = timerID
        self.doodleImageData = doodleImageData
    }
}
#else
import Foundation

/// Stub so `swift build` / `DrawnTimerEngine` tests succeed on macOS; Live Activity models are iOS-only.
public enum DrawnActivityModelsStub: Sendable {
    case iOSOnly
}
#endif
