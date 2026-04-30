import AppIntents
import Foundation

@available(iOS 17, *)
public struct ToggleDrawnTimerIntent: AppIntent, LiveActivityIntent {
    public static var title: LocalizedStringResource = "Pause or resume"
    public static var isDiscoverable: Bool { false }

    /// Do not foreground Drawn — mirror `Toggle` from the Dynamic Island without opening the app.
    public static var openAppWhenRun: Bool { false }

    @Parameter(title: "Timer id")
    public var timerID: String

    public init() {
        timerID = ""
    }

    public init(timerID: String) {
        self.timerID = timerID
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        guard let id = StopDrawnTimerIntent.parseUUID(timerID) else {
            return .result()
        }
        // Main app already applies the toggle synchronously via `TimerIntentCallbacks`. Recording a pending UUID here
        // would duplicate the flip when `drainPendingExtensionIntents()` runs — wrong state vs lock-screen.
        if let toggle = TimerIntentCallbacks.onToggleTimer {
            toggle(id)
        } else {
            PendingIntentBridge.recordPendingToggle(id)
            DrawnDarwinAlarmDismissBridge.postToggleRequestFromExtensionIntent()
        }
        return .result()
    }
}
