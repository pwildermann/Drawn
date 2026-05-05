import Foundation

public struct TimerLifecycleState: Equatable, Sendable {
    public var totalSeconds: Int
    public var remainingSeconds: Int
    public var isRunning: Bool
    public var hasStarted: Bool
    public var isRinging: Bool

    public init(totalSeconds: Int) {
        self.totalSeconds = max(0, totalSeconds)
        self.remainingSeconds = max(0, totalSeconds)
        self.isRunning = false
        self.hasStarted = false
        self.isRinging = false
    }
}

public enum TimerLifecycleAction: Sendable {
    case start
    case pause
    case resume
    case stop
    case tick(seconds: Int)
}

public enum TimerLifecycleEngine {
    /// Pure state machine for core timer behavior. Mirrors app-level semantics without side effects.
    public static func reduce(_ state: TimerLifecycleState, action: TimerLifecycleAction) -> TimerLifecycleState {
        var next = state
        switch action {
        case .start:
            guard !next.isRinging else { return next }
            next.isRunning = true
            next.hasStarted = true
        case .pause:
            guard !next.isRinging else { return next }
            next.isRunning = false
        case .resume:
            guard !next.isRinging else { return next }
            guard next.remainingSeconds > 0 else { return next }
            next.isRunning = true
            next.hasStarted = true
        case .stop:
            next.isRunning = false
            next.hasStarted = false
            next.isRinging = false
            next.remainingSeconds = next.totalSeconds
        case .tick(let seconds):
            let delta = max(0, seconds)
            guard delta > 0 else { return next }
            guard next.isRunning else { return next }
            let updated = max(0, next.remainingSeconds - delta)
            next.remainingSeconds = updated
            if updated == 0 {
                next.isRunning = false
                next.hasStarted = false
                next.isRinging = true
                next.remainingSeconds = next.totalSeconds
            }
        }
        return next
    }
}
