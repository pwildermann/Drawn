import Foundation
import UserNotifications

/// Schedules **one local notification per running timer** at its wall-clock end so iOS plays **sound** and (**per system settings**) **vibration** when the handset is muted. `TimerAlarmService` only runs in-process; **`UNUserNotification`** is what fires when suspended.
///
/// Alerts are deliberately minimal (**title-only** — no long body): Live Activity + Dynamic Island remain the rich UI.
@MainActor
final class TimerFireNotificationService {
    static let shared = TimerFireNotificationService()

    private init() {}

    private static func requestIdentifier(for timerID: UUID) -> String {
        "drawn.timer.fire.\(timerID.uuidString)"
    }

    private func schedulingIsAllowed(for settings: UNNotificationSettings) -> Bool {
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    /// Runs only when **`notDetermined`** — used after the in-app primer sheet. Does **not** prompt if the user already chose allow/deny.
    func requestAuthorizationThroughSystemPromptIfEligible() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.sound, .alert])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func syncScheduledNotifications(timers: [DrawnTimer], deadlineByID: [UUID: Date]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard schedulingIsAllowed(for: settings) else { return }

        for timer in timers {
            guard timer.isRunning, timer.remainingSeconds > 0 else {
                removeAll(for: timer.id)
                continue
            }

            let fireDate = deadlineByID[timer.id] ?? Date().addingTimeInterval(TimeInterval(timer.remainingSeconds))
            guard fireDate.timeIntervalSinceNow > 0.75 else {
                removeAll(for: timer.id)
                continue
            }

            let content = UNMutableNotificationContent()

            content.title = NSLocalizedString("Timer ended", comment: "Local notification title when a timer reaches zero")
            content.body = ""

            content.sound = UNNotificationSound.default

            let interval = fireDate.timeIntervalSinceNow
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.5, interval), repeats: false)

            let request = UNNotificationRequest(
                identifier: Self.requestIdentifier(for: timer.id),
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {}
        }
    }

    func removeAll(for timerID: UUID) {
        let id = Self.requestIdentifier(for: timerID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }
}
