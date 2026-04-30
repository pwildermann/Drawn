import Foundation

/// App-intent entry point bound weakly from ``TimerStore`` so extensions never retain the store.
@MainActor
protocol TimerIntentCommanding: AnyObject {
    func toggleTimer(_ id: UUID)
    func resetTimer(_ id: UUID)
}
