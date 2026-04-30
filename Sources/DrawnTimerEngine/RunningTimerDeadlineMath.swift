import Foundation

public enum RunningTimerDeadlineMath {
    /// Remaining whole seconds until `deadline` relative to `now` (ceil toward +∞, floored at 0).
    public static func remainingSecondsUntil(deadline: Date, now: Date) -> Int {
        max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }
}
