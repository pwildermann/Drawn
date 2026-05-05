import Foundation

/// Canonical routes used by Live Activity controls (`drawn://<route>?id=`).
public enum LiveActivityControlRoute: String, CaseIterable, Sendable {
    case stop
    case pause
    case resume
    case toggle

    /// Accepts host/path tokens from deep links.
    public init?(token: String) {
        self.init(rawValue: token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// `pause` / `resume` are idempotent. `toggle` remains supported for backward compatibility.
    public func resultingRunningState(currentRunning: Bool) -> Bool? {
        switch self {
        case .stop:
            return nil
        case .pause:
            return false
        case .resume:
            return true
        case .toggle:
            return !currentRunning
        }
    }

    /// Route to render for the play/pause control based on current timer state.
    public static func playPauseRoute(isPaused: Bool) -> LiveActivityControlRoute {
        isPaused ? .resume : .pause
    }
}
