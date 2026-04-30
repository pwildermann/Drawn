import CoreFoundation
import Foundation

/// Cross-process “user tapped stop” from the widget extension Live Activity intent → main app **without**
/// relying on extension `UserDefaults.standard` matching the host app (those are **different sandboxes**).
///
/// Keeps **`PendingIntentBridge` + App Group** as extra delivery when configured; Darwin notify works when App Group isn’t set.
enum DrawnDarwinAlarmDismissBridge {
    private static let notificationName = "com.timer.drawn.alarmDismissRequest" as CFString

    private static let observerCallback: CFNotificationCallback = { _, _, _, _, _ in
        DispatchQueue.main.async {
            mainProcessHandler?()
        }
    }

    /// Main-app callback (must run UI / `TimerAlarmService`); invoked on **main**.
    nonisolated(unsafe) private static var mainProcessHandler: (() -> Void)?

    private static var didInstallObserver = false

    /// Call once from the main app (`TimerStore.init`).
    static func installMainProcessListener(handler: @escaping () -> Void) {
        guard !didInstallObserver else { return }
        didInstallObserver = true
        mainProcessHandler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            observerCallback,
            notificationName,
            nil,
            .deliverImmediately
        )
    }

    /// Call from `StopDrawnTimerIntent` when `DrawnIntentsRuntime.onStopTimer == nil` (runs in Live Activity widget extension).
    static func postDismissRequestFromExtensionIntent() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: notificationName),
            nil,
            nil,
            true
        )
    }
}
