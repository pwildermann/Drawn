import Foundation

/// Inputs required to pick which timer should drive the Dynamic Island when not ringing.
public struct PrimaryTimerPickInput: Hashable, Sendable {
    public let id: UUID
    public let hasStarted: Bool
    public let isRunning: Bool
    public let remainingSeconds: Int

    public init(id: UUID, hasStarted: Bool, isRunning: Bool, remainingSeconds: Int) {
        self.id = id
        self.hasStarted = hasStarted
        self.isRunning = isRunning
        self.remainingSeconds = remainingSeconds
    }
}

/// Chooses **one** timer for Live Activity (same rules as ``TimerStore``):
/// - While **any** timer is **running**, prefer **running** timers only (soonest-finishing wins).
/// - When none run, whichever **started** pause is nearest zero (`remainingSeconds`), excluding zeros.
/// - **Session** timers are **`hasStarted || isRunning`** so a running countdown never drops out of the pool if those flags desync (otherwise reconciliation uses **`primary: nil`** and **ends** the Live Activity).
public enum PrimaryTimerPicker {
    public static func preferredTimerID(from timers: [PrimaryTimerPickInput]) -> UUID? {
        let started = timers.filter { $0.hasStarted || $0.isRunning }
        guard !started.isEmpty else { return nil }

        let running = started.filter(\.isRunning)
        let pool = running.isEmpty ? started.filter { $0.remainingSeconds > 0 } : running
        guard !pool.isEmpty else { return nil }

        return pool.min(by: { $0.remainingSeconds < $1.remainingSeconds })?.id
    }
}
