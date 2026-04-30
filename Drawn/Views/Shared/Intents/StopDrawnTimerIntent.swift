import AppIntents
import Foundation

/// Must be `public` so the runtime can resolve the intent when handling Live Activity buttons (Debug & Release).
@available(iOS 17, *)
public struct StopDrawnTimerIntent: AppIntent, LiveActivityIntent {
    public static var title: LocalizedStringResource = "Stop timer"
    public static var isDiscoverable: Bool { false }
    /// **`false`** — dismiss from Live Activity / Dynamic Island should stop the timer **without** switching to the app;
    /// when the intent runs in the widget extension, **`PendingIntentBridge`** + **`DrawnDarwinAlarmDismissBridge`** deliver the stop to **`TimerStore`**.
    public static var openAppWhenRun: Bool { false }

    @Parameter(title: "Timer id")
    public var timerID: String

    public init() {
        timerID = ""
    }

    public init(timerID: String) {
        self.timerID = timerID
    }

    public func perform() async throws -> some IntentResult {
        guard let id = StopDrawnTimerIntent.parseUUID(timerID) else {
            return .result()
        }
        await MainActor.run {
            // Don’t enqueue when already handling in-process — foreground drain would replay the reset.
            if let stop = TimerIntentCallbacks.onStopTimer {
                stop(id)
            } else {
                PendingIntentBridge.recordPendingStop(id)
                // Extension process: `UserDefaults.standard` is not the app’s sandbox; App Group + Darwin bridge deliver stop.
                DrawnDarwinAlarmDismissBridge.postStopRequestFromExtensionIntent()
            }
        }
        return .result()
    }

    /// App Intents occasionally alter string casing/format — accept common variants.
    static func parseUUID(_ raw: String) -> UUID? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = UUID(uuidString: t) { return u }
        if let u = UUID(uuidString: t.lowercased()) { return u }
        if let u = UUID(uuidString: t.uppercased()) { return u }
        return nil
    }
}
