import Foundation

public enum RunningTimerDeadlineMath {
    /// Remaining whole seconds until `deadline` relative to `now` (ceil toward +∞, floored at 0).
    public static func remainingSecondsUntil(deadline: Date, now: Date) -> Int {
        max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    /// Adjusts a previously persisted remaining value by elapsed wall-clock time.
    /// Result is always clamped to 0 so callers can safely pause timers after cold launch.
    public static func remainingAfterElapsed(savedRemainingSeconds: Int, elapsedSeconds: Int) -> Int {
        max(0, savedRemainingSeconds - max(0, elapsedSeconds))
    }
}
