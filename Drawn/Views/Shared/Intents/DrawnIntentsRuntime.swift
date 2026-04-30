import Foundation

/// Set from ``TimerStore`` after init. ``StopDrawnTimerIntent`` / ``ToggleDrawnTimerIntent`` call these from `perform()`.
@MainActor
enum DrawnIntentsRuntime {
    static var onToggleTimer: ((UUID) -> Void)?
    static var onStopTimer: ((UUID) -> Void)?
}
