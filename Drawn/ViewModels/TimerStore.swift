import Combine
import Foundation
import UIKit
import UserNotifications

@MainActor
final class TimerStore: ObservableObject {
    @Published var timers: [DrawnTimer] = []

    /// Shown once after the **first** time any timer transitions to running (primer before the OS notification prompt).
    @Published private(set) var presentNotificationPermissionPrimer = false

    /// Wall-clock deadlines (`now + remaining` at snapshot) — used to **`resync`** `remainingSeconds` after suspend and for periodic background heals (**no** per‑second **`activity.update`**).
    private var runningDeadlineByTimerID: [UUID: Date] = [:]

    /// Coarse background wake (**~60 s**, main run loop) **`resync`** + **`activity.update`** so Live Activity **`ContentState.endDate`** matches wall time (`Text(_, style: .timer)` animates toward that absolute date).
    private var backgroundLiveActivityHealTimer: Timer?

    /// One-shot at the soonest running wall-clock deadline so completion fires when **`tick`** doesn’t (**`ringing`** + alarm + LA update vs. stale **`endDate`**).
    private var backgroundWallClockExpiryTimer: Timer?

    /// Snapshot of the timer that just hit zero; shown in the Live Activity until dismissed.
    private var ringingSession: DrawnTimer? {
        didSet { ringingAlarmTimerIDForUI = ringingSession?.id }
    }

    /// Drives foreground “expanded island” parity UI — ActivityKit often does not promote the Dynamic Island alert while your own app stays active.
    @Published private(set) var ringingAlarmTimerIDForUI: UUID?

    private var tickTimer: DispatchSourceTimer?
    private var ringingIntentDrainTimer: DispatchSourceTimer?
    private var saveCancellable: AnyCancellable?

    /// Mirrors which timer **`LiveActivityService`** shows (ringing id, else primary running/paused). Used to avoid **`activity.update`** on every **`tick`** while still reacting when **`primaryTimerForLiveActivity()`** changes.
    private var lastSyncedLiveActivityTargetID: UUID?

    init() {
        timers = TimerPersistenceService.shared.load()

        let tick = DispatchSource.makeTimerSource(queue: .main)
        tick.schedule(deadline: .now() + 1, repeating: 1.0, leeway: .milliseconds(25))
        tick.setEventHandler { [weak self] in
            self?.tick()
        }
        tick.resume()
        tickTimer = tick

        saveCancellable = $timers
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { TimerPersistenceService.shared.save($0) }

        // After all stored state is initialized: strong `[self]` so Live Activity intents always reach `resetTimer` (`[weak self]` could be nil while the alarm runs).
        DrawnIntentsRuntime.onToggleTimer = { [self] id in self.toggleTimer(id) }
        DrawnIntentsRuntime.onStopTimer = { [self] id in self.resetTimer(id) }

        DrawnDarwinAlarmDismissBridge.installMainProcessListener { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleDarwinDismissFromLiveActivityExtension()
            }
        }

        drainPendingExtensionIntents()

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.snapRunningDeadlinesToWallClockNow()
                // One push refreshes **`endDate`/`contentPushEpoch`** for the widget (not per‑second).
                self.syncLiveActivityWithModel()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.invalidateBackgroundLiveActivityHealTimer()
                self.invalidateBackgroundWallClockExpiryTimer()
                self.resyncRunningRemainingSecondsFromStoredDeadlines()
                self.finalizeRunningTimersExpiredByWallClock()
                self.syncLiveActivityWithModel()
            }
        }

        syncLiveActivityWithModel()
    }

    /// Pushes Live Activity when user-driven state changes ring; snaps deadlines for foreground math.
    private func syncLiveActivityWithModel() {
        reconcileLiveActivity()
        snapRunningDeadlinesToWallClockNow()
        lastSyncedLiveActivityTargetID = ringingSession?.id ?? primaryTimerForLiveActivity()?.id
        scheduleBackgroundLiveActivityHealTimerIfNeeded()
        scheduleBackgroundWallClockExpiryTimerIfNeeded()
        refreshScheduledFireNotifications()
    }

    private func refreshScheduledFireNotifications() {
        Task {
            await TimerFireNotificationService.shared.syncScheduledNotifications(
                timers: timers,
                deadlineByID: runningDeadlineByTimerID
            )
        }
    }

    private func clearFireNotificationForTimerEnded(_ timerID: UUID) {
        TimerFireNotificationService.shared.removeAll(for: timerID)
    }

    private func invalidateBackgroundWallClockExpiryTimer() {
        backgroundWallClockExpiryTimer?.invalidate()
        backgroundWallClockExpiryTimer = nil
    }

    /// Runs after **`snapRunningDeadlinesToWallClockNow()`** populated **`runningDeadlineByTimerID`** (call from **`syncLiveActivityWithModel`** tail).
    private func scheduleBackgroundWallClockExpiryTimerIfNeeded() {
        invalidateBackgroundWallClockExpiryTimer()
        guard UIApplication.shared.applicationState == .background else { return }
        guard ringingSession == nil else { return }
        guard let soonest = runningDeadlineByTimerID.values.min() else { return }

        let delay = soonest.timeIntervalSinceNow
        if delay <= 0 {
            Task { @MainActor [weak self] in
                self?.fireBackgroundWallClockExpiryTimer()
            }
            return
        }

        backgroundWallClockExpiryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fireBackgroundWallClockExpiryTimer() }
        }
    }

    private func fireBackgroundWallClockExpiryTimer() {
        guard UIApplication.shared.applicationState == .background else {
            invalidateBackgroundWallClockExpiryTimer()
            return
        }
        applyBackgroundDeadlineResyncReconcileAndSyncMeta()
        scheduleBackgroundWallClockExpiryTimerIfNeeded()
    }

    /// Shared path for **`heal`** tick and **`…Expiry`** fires: wall-clock **`0`** without **`tick`** ⇒ complete timers + ringing LA (**not** **`endDate`** in the past / SwiftUI timer count-up ).
    private func applyBackgroundDeadlineResyncReconcileAndSyncMeta() {
        guard UIApplication.shared.applicationState == .background else { return }
        resyncRunningRemainingSecondsFromStoredDeadlines()
        finalizeRunningTimersExpiredByWallClock()
        reconcileLiveActivity()
        snapRunningDeadlinesToWallClockNow()
        lastSyncedLiveActivityTargetID = ringingSession?.id ?? primaryTimerForLiveActivity()?.id
        refreshScheduledFireNotifications()
    }

    private func invalidateBackgroundLiveActivityHealTimer() {
        backgroundLiveActivityHealTimer?.invalidate()
        backgroundLiveActivityHealTimer = nil
    }

    /// Periodic heal while **`UIApplicationState.background`** : **`tick`** stops → model vs wall-clock drift **`endDate`**; **`Text(_, style: .timer)`** only matches if **`ContentState.endDate`** is pushed periodically (not once per second).
    private func scheduleBackgroundLiveActivityHealTimerIfNeeded() {
        invalidateBackgroundLiveActivityHealTimer()
        guard UIApplication.shared.applicationState == .background else { return }
        guard ringingSession != nil || timers.contains(where: { $0.isRunning }) else { return }

        backgroundLiveActivityHealTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.backgroundLiveActivityHealTick()
            }
        }
    }

    private func backgroundLiveActivityHealTick() {
        guard UIApplication.shared.applicationState == .background else {
            invalidateBackgroundLiveActivityHealTimer()
            return
        }
        applyBackgroundDeadlineResyncReconcileAndSyncMeta()
        scheduleBackgroundWallClockExpiryTimerIfNeeded()
    }

    /// Fire deadline (= wall now + remaining) — used after ticks & before background snapshot.
    private func snapRunningDeadlinesToWallClockNow() {
        runningDeadlineByTimerID.removeAll(keepingCapacity: true)
        for timer in timers where timer.isRunning {
            runningDeadlineByTimerID[timer.id] = Date().addingTimeInterval(TimeInterval(timer.remainingSeconds))
        }
    }

    /// After suspension, **`tick`** may have missed seconds — realign **`remainingSeconds`** from the last **`…EnterBackground`** snapshot.
    private func resyncRunningRemainingSecondsFromStoredDeadlines() {
        guard !runningDeadlineByTimerID.isEmpty else {
            snapRunningDeadlinesToWallClockNow()
            return
        }
        for idx in timers.indices where timers[idx].isRunning {
            guard let deadline = runningDeadlineByTimerID[timers[idx].id] else { continue }
            timers[idx].remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        }
    }

    /// **`tick()`** may not fire while suspended, but **`resync…`** can set **`remainingSeconds == 0`** with **`isRunning == true`**.
    /// If we reconcile before completing, **`LiveActivity`** gets **`endDate ≈ now`**, **`Text(_, style: .timer)`** then runs **past** that date and appears to **count up** — and the **ringing** state never replaces it.
    @discardableResult
    private func finalizeRunningTimersExpiredByWallClock() -> Bool {
        var didEnterRinging = false
        for index in timers.indices where timers[index].isRunning && timers[index].remainingSeconds <= 0 {
            let timerID = timers[index].id
            let finished = timers[index]
            ringingSession = finished
            didEnterRinging = true
            timers[index].isRunning = false
            timers[index].hasStarted = false
            timers[index].remainingSeconds = timers[index].duration.totalSeconds
            clearFireNotificationForTimerEnded(timerID)
            TimerAlarmService.shared.start(for: timerID)
        }
        if didEnterRinging {
            syncRingingIntentDrain(withRinging: ringingSession != nil)
        }
        return didEnterRinging
    }

    /// Call when the scene becomes active so pending stop/toggle from the widget extension (App Group / cold launch) drain into `TimerStore`.
    func drainPendingExtensionIntents() {
        while let id = PendingIntentBridge.consumePendingStop() {
            resetTimer(id)
        }
        for id in PendingIntentBridge.dequeueAllPendingToggleUUIDs() {
            toggleTimer(id)
        }
    }

    private func ensureRingingIntentDrainStarted() {
        guard ringingIntentDrainTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 0.2, leeway: .milliseconds(40))
        t.setEventHandler { [weak self] in
            self?.drainPendingExtensionIntents()
        }
        t.resume()
        ringingIntentDrainTimer = t
    }

    private func stopRingingIntentDrain() {
        ringingIntentDrainTimer?.cancel()
        ringingIntentDrainTimer = nil
    }

    /// Live Activity intents often run only in the widget extension (`onStopTimer` / `onToggleTimer` nil there). Darwin notify + polling see `PendingIntentBridge`.
    private func handleDarwinDismissFromLiveActivityExtension() {
        drainPendingExtensionIntents()
        if let id = ringingSession?.id {
            resetTimer(id)
            return
        }
        TimerAlarmService.shared.stop(for: nil)
    }

    /// Call whenever `ringingSession` may have changed outside `tick()` (already covered at end of `tick`).
    private func syncRingingIntentDrain(withRinging: Bool) {
        if withRinging { ensureRingingIntentDrainStarted() } else { stopRingingIntentDrain() }
    }

    func addTimer(name: String, duration: TimerDuration, doodleData: Data?) {
        timers.append(DrawnTimer(name: name, duration: duration, doodleData: doodleData))
    }

    func updateTimer(id: UUID, duration: TimerDuration, doodleData: Data?) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let durationChanged = timers[index].duration != duration
        timers[index].duration = duration
        timers[index].doodleData = doodleData
        if durationChanged {
            if ringingSession?.id == id {
                ringingSession = nil
                stopRingingIntentDrain()
            }
            timers[index].remainingSeconds = duration.totalSeconds
            timers[index].isRunning = false
            timers[index].hasStarted = false
        } else if var s = ringingSession, s.id == id {
            s.name = timers[index].name
            s.doodleData = timers[index].doodleData
            s.duration = timers[index].duration
            ringingSession = s
        }
        syncLiveActivityWithModel()
    }

    func deleteTimer(_ timerID: UUID) {
        if ringingSession?.id == timerID {
            ringingSession = nil
            stopRingingIntentDrain()
        }
        TimerAlarmService.shared.stop(for: timerID)
        TimerFireNotificationService.shared.removeAll(for: timerID)
        timers.removeAll { $0.id == timerID }
        syncLiveActivityWithModel()
    }

    func resetTimer(_ timerID: UUID) {
        // Always silence alarm audio first (single global alarm); also covers intent ID mismatch vs `timers`.
        TimerAlarmService.shared.stop(for: nil)
        if ringingSession?.id == timerID {
            ringingSession = nil
            stopRingingIntentDrain()
        }
        guard let index = timers.firstIndex(where: { $0.id == timerID }) else {
            syncLiveActivityWithModel()
            return
        }
        timers[index].isRunning = false
        timers[index].hasStarted = false
        timers[index].remainingSeconds = timers[index].duration.totalSeconds
        syncLiveActivityWithModel()
    }

    func toggleTimer(_ timerID: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == timerID }) else { return }
        // Dismiss ringing via Stop / reset only — toggle must not flip `isRunning` while the alarm session
        // is active (looks like “timer restarted”). Ringing-intent polling also drains stale pending toggles.
        if ringingSession?.id == timerID {
            return
        }
        let wasRunning = timers[index].isRunning
        timers[index].isRunning.toggle()
        if timers[index].isRunning {
            timers[index].hasStarted = true
        }
        if timers[index].isRunning, !wasRunning,
           !DrawnNotificationPermissionEducation.hasFinishedPrimerFlow
        {
            presentNotificationPermissionPrimer = true
        }
        syncLiveActivityWithModel()
    }

    func dismissNotificationPermissionPrimer() {
        presentNotificationPermissionPrimer = false
    }

    /// Call after primer dismiss / backdrop tap — runs **`UNUserNotificationCenter`** prompt when still undecided, then reschedules fire notifications if authorized.
    func resumeNotificationSchedulingAfterEducationSheet() async {
        _ = await TimerFireNotificationService.shared.requestAuthorizationThroughSystemPromptIfEligible()
        refreshScheduledFireNotifications()
    }

    // MARK: - Live Activity

    /// Chooses **one** timer for Dynamic Island — must agree with users’ intuition when scanning home cards:
    ///
    /// - While **any timer is running**, the island reflects **running** timers only (soonest-finishing wins).
    /// - When none are running, whichever started pause is nearest zero (paused countdown).
    private func primaryTimerForLiveActivity() -> DrawnTimer? {
        let started = timers.filter(\.hasStarted)
        guard !started.isEmpty else { return nil }

        let running = started.filter(\.isRunning)
        let pool = running.isEmpty ? started.filter { $0.remainingSeconds > 0 } : running
        guard !pool.isEmpty else { return nil }

        return pool.min(by: { $0.remainingSeconds < $1.remainingSeconds })
    }

    func reconcileLiveActivity() {
        if let r = ringingSession {
            LiveActivityService.shared.reconcile(ringing: r, primary: nil)
        } else if let p = primaryTimerForLiveActivity() {
            LiveActivityService.shared.reconcile(ringing: nil, primary: p)
        } else {
            LiveActivityService.shared.reconcile(ringing: nil, primary: nil)
        }
    }

    // MARK: - Tick

    private func tick() {
        var didEnterRinging = false
        for index in timers.indices where timers[index].isRunning {
            if timers[index].remainingSeconds > 0 {
                timers[index].remainingSeconds -= 1
            } else {
                let timerID = timers[index].id
                let finished = timers[index]
                ringingSession = finished
                didEnterRinging = true
                timers[index].isRunning = false
                timers[index].hasStarted = false
                timers[index].remainingSeconds = timers[index].duration.totalSeconds
                clearFireNotificationForTimerEnded(timerID)
                TimerAlarmService.shared.start(for: timerID)
            }
        }

        syncRingingIntentDrain(withRinging: ringingSession != nil)

        if UIApplication.shared.applicationState == .active {
            snapRunningDeadlinesToWallClockNow()
        }

        let laTargetNow = ringingSession?.id ?? primaryTimerForLiveActivity()?.id

        // No per-second **`activity.update`** when foreground/active (freezes + fights **`Text(_, style: .timer)`**). Background uses **`scheduleBackgroundLiveActivityHealTimerIfNeeded`** instead.
        // Push when ringing starts, **or** when the island’s logical timer swaps (e.g. two running timers, soonest-finishing crosses over).
        if didEnterRinging || laTargetNow != lastSyncedLiveActivityTargetID {
            syncLiveActivityWithModel()
        }
    }
}

// MARK: - Notification permission primer (same target as `TimerStore`; avoids duplicate-type clashes with stray files in the project)

/// Tracks whether the user has completed the in-app explainer before the **system** notifications prompt (`UserDefaults`).
enum DrawnNotificationPermissionEducation {
    /// Intentionally **unchanged** so existing installs keep primer state across refactors.
    private static let completedKey = "drawn.notifications.permissionEducation.completed"

    static var hasFinishedPrimerFlow: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markPrimerFlowFinished() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// Legacy installs: permission was already resolved before we added the primer — skip the sheet once.
    static func skipPrimerWhenAuthorizationAlreadyResolved() async {
        guard !hasFinishedPrimerFlow else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return
        default:
            markPrimerFlowFinished()
        }
    }
}
