import Foundation

/// Queues **stop** or **toggle** UUIDs when the intent runs before `TimerStore` wires `TimerIntentCallbacks`,
/// or when the intent executes in the widget extension (different `UserDefaults.standard` sandbox than the app).
///
/// **Setup:** Add the same App Group to **Drawn** and **DrawnWidgetExtension**, then set on **both** Info.plists:
///
/// - Key: `DrawnPendingIntentAppGroup` (String)
/// - Value: `group.your.bundle.id` (must match Signing & Capabilities → App Groups)
///
/// Without the key, only `UserDefaults.standard` is used (fine when the intent runs in the main app process).
enum PendingIntentBridge {
    private static let stopKey = "Drawn.pendingStopTimerUUID"
    /// Legacy single toggle (older builds overwrote on each tap — lost rapid pause+resume).
    private static let toggleKey = "Drawn.pendingToggleTimerUUID"
    private static let toggleQueueKey = "Drawn.pendingToggleTimerUUID.Queue"

    private static var sharedSuite: UserDefaults? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "DrawnPendingIntentAppGroup") as? String,
              !id.isEmpty else {
            return nil
        }
        return UserDefaults(suiteName: id)
    }

    static func recordPendingStop(_ id: UUID) {
        let value = id.uuidString
        UserDefaults.standard.set(value, forKey: stopKey)
        sharedSuite?.set(value, forKey: stopKey)
    }

    static func consumePendingStop() -> UUID? {
        if let suite = sharedSuite, let s = suite.string(forKey: stopKey), let u = UUID(uuidString: s) {
            suite.removeObject(forKey: stopKey)
            UserDefaults.standard.removeObject(forKey: stopKey)
            return u
        }
        guard let s = UserDefaults.standard.string(forKey: stopKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: stopKey)
        return UUID(uuidString: s)
    }

    // MARK: - Toggle queue

    static func recordPendingToggle(_ id: UUID) {
        var q = readToggleQueue()
        migrateLegacySingletonToggleIfNeeded(into: &q)
        q.append(id.uuidString)
        writeToggleQueue(q)
    }

    /// Every pending toggle in order (rapid lock-screen pause then resume yields two entries), then clears storage.
    static func dequeueAllPendingToggleUUIDs() -> [UUID] {
        var q = readToggleQueue()
        migrateLegacySingletonToggleIfNeeded(into: &q)
        writeToggleQueue([])
        return q.compactMap { UUID(uuidString: $0) }
    }

    private static func readToggleQueue() -> [String] {
        if let suite = sharedSuite, let a = suite.array(forKey: toggleQueueKey) as? [String], !a.isEmpty {
            return a
        }
        if let a = UserDefaults.standard.array(forKey: toggleQueueKey) as? [String], !a.isEmpty {
            return a
        }
        return []
    }

    private static func writeToggleQueue(_ q: [String]) {
        if q.isEmpty {
            sharedSuite?.removeObject(forKey: toggleQueueKey)
            UserDefaults.standard.removeObject(forKey: toggleQueueKey)
        } else {
            sharedSuite?.set(q, forKey: toggleQueueKey)
            UserDefaults.standard.set(q, forKey: toggleQueueKey)
        }
    }

    /// If an older build left a single UUID under `toggleKey`, fold it in once at the front of the queue.
    private static func migrateLegacySingletonToggleIfNeeded(into q: inout [String]) {
        if let suite = sharedSuite, let s = suite.string(forKey: toggleKey), let u = UUID(uuidString: s) {
            suite.removeObject(forKey: toggleKey)
            UserDefaults.standard.removeObject(forKey: toggleKey)
            q.insert(u.uuidString, at: 0)
            return
        }
        if let s = UserDefaults.standard.string(forKey: toggleKey), let u = UUID(uuidString: s) {
            UserDefaults.standard.removeObject(forKey: toggleKey)
            q.insert(u.uuidString, at: 0)
        }
    }
}
