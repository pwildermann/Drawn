import CoreFoundation
import Foundation

/// Cross-process “user tapped stop” from the widget extension Live Activity intent → main app **without**
/// relying on extension `UserDefaults.standard` matching the host app (those are **different sandboxes**).
///
/// Keeps **`PendingIntentBridge` + App Group** as extra delivery when configured; Darwin notify works when App Group isn’t set.
enum DrawnDarwinAlarmDismissBridge {
    enum Action {
        case stop
        case toggle
    }

    private static let stopNotificationName = "com.timer.drawn.alarmStopRequest" as CFString
    private static let toggleNotificationName = "com.timer.drawn.alarmToggleRequest" as CFString

    private static let stopObserverCallback: CFNotificationCallback = { _, _, _, _, _ in
        DispatchQueue.main.async { mainProcessHandler?(.stop) }
    }

    private static let toggleObserverCallback: CFNotificationCallback = { _, _, _, _, _ in
        DispatchQueue.main.async { mainProcessHandler?(.toggle) }
    }

    /// Main-app callback (must run UI / `TimerAlarmService`); invoked on **main**.
    nonisolated(unsafe) private static var mainProcessHandler: ((Action) -> Void)?

    private static var didInstallObserver = false

    /// Call once from the main app (`TimerStore.init`).
    static func installMainProcessListener(handler: @escaping (Action) -> Void) {
        guard !didInstallObserver else { return }
        didInstallObserver = true
        mainProcessHandler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            stopObserverCallback,
            stopNotificationName,
            nil,
            .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            toggleObserverCallback,
            toggleNotificationName,
            nil,
            .deliverImmediately
        )
    }

    /// Call from `StopDrawnTimerIntent` when `TimerIntentCallbacks.onStopTimer == nil` (runs in Live Activity widget extension).
    static func postStopRequestFromExtensionIntent() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: stopNotificationName),
            nil,
            nil,
            true
        )
    }

    /// Call from `ToggleDrawnTimerIntent` when `TimerIntentCallbacks.onToggleTimer == nil`.
    static func postToggleRequestFromExtensionIntent() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: toggleNotificationName),
            nil,
            nil,
            true
        )
    }
}
