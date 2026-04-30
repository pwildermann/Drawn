import Foundation

/// Set from ``TimerStore`` after init. ``StopDrawnTimerIntent`` / ``ToggleDrawnTimerIntent`` call these from `perform()`.
///
/// **Naming:** Avoid `DrawnIntentsRuntime` — Xcode / App Intents can synthesize that identifier and shadow this type.
@MainActor
enum TimerIntentCallbacks {
    static var onToggleTimer: ((UUID) -> Void)?
    static var onStopTimer: ((UUID) -> Void)?
}
