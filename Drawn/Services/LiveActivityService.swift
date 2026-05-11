import ActivityKit
import DrawnActivityModels
import Foundation
import PencilKit
import UIKit

/// Keeps **at most one** Live Activity, always for the timer that should be in the Dynamic Island:
/// ringing (until dismissed) takes priority, otherwise **`TimerStore`’s primary** —
/// among **running** timers, the soonest-finishing one; when none run, whichever started pause is nearest zero.
@MainActor
final class LiveActivityService {
    static let shared = LiveActivityService()
    private init() {}
    private var reconcileBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// Bump when thumbnail rasterization logic changes so we don’t keep serving stale JPEGs per doodle hash.
    private let doodleRasterVersion = 6
    private var doodleRenderCache: [String: (hash: Int, ver: Int, data: Data?)] = [:]

    /// One `AlertConfiguration` when ringing begins (paired with `takeRingingIslandAlertIfNeeded()`).
    private var ringingIslandAlertEmittedForTimerID: UUID?

    private var nextContentPushEpoch: UInt64 = 0

    private func nextContentPushEpochValue() -> UInt64 {
        nextContentPushEpoch &+= 1
        return nextContentPushEpoch
    }

    // MARK: - Reconcile

    /// Serializes reconcile work. **`fetch` runs only after** awaiting the previous task so pushed `DrawnTimer` state matches **`TimerStore`’s latest model** (avoids out‑of‑order `ContentState` after **`tick`**).
    /// Ringing takes priority over primary.
    private var reconcileChainTask: Task<Void, Never>?

    func reconcile(fetch: @escaping @MainActor () -> (ringing: DrawnTimer?, primary: DrawnTimer?)) {
        let previous = reconcileChainTask
        reconcileChainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let backgroundTaskID = self.beginReconcileBackgroundTaskIfNeeded()
            defer { self.endReconcileBackgroundTask(backgroundTaskID) }
            if let previous {
                await previous.value
            }
            let (ringingSnap, primarySnap) = fetch()
            if ringingSnap == nil {
                self.ringingIslandAlertEmittedForTimerID = nil
            }
            if let r = ringingSnap {
                await self.endActivitiesAsync(where: { $0 != r.id })
                await self.updateOrRequestRinging(r)
            } else if let p = primarySnap {
                let hasActivity = self.activity(for: p.id) != nil
                let appActive = UIApplication.shared.applicationState == .active
                if hasActivity || appActive {
                    await self.endActivitiesAsync(where: { $0 != p.id })
                }
                await self.updateOrRequestPrimary(p)
            } else {
                // Background can transiently deliver no model snapshot during lifecycle churn.
                // Avoid destructive end-all outside foreground; reconcile will correct on next active pass.
                if UIApplication.shared.applicationState == .active {
                    await self.endAllActivitiesAsync()
                }
            }
        }
    }

    /// Explicit cleanup path for user-driven ring dismissal/reset so stale `0:00` activities
    /// cannot survive until a later reconcile pass.
    func forceEndAllActivities() {
        let previous = reconcileChainTask
        reconcileChainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let backgroundTaskID = self.beginReconcileBackgroundTaskIfNeeded()
            defer { self.endReconcileBackgroundTask(backgroundTaskID) }
            if let previous {
                await previous.value
            }
            self.ringingIslandAlertEmittedForTimerID = nil
            await self.endAllActivitiesAsync()
        }
    }

    // MARK: - Private

    /// Promotes the ringing update so iPhone shows the **expanded** Dynamic Island (AlertConfiguration update).
    private func ringingIslandAlertConfiguration() -> AlertConfiguration {
        AlertConfiguration(
            title: LocalizedStringResource("Timer ended"),
            body: LocalizedStringResource("Tap to dismiss or stop."),
            sound: .default
        )
    }

    private func updateOrRequestRinging(_ timer: DrawnTimer) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let imageData = thumbnailJPEGForActivityAttributes(from: timer)
        let state = ringingContentState(from: timer)
        let ringingContent = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)

        // One alert per ringing session: expanded Dynamic Island / lock-screen prominence via ActivityKit alert.
        func takeRingingIslandAlertIfNeeded() -> AlertConfiguration? {
            guard ringingIslandAlertEmittedForTimerID != timer.id else { return nil }
            ringingIslandAlertEmittedForTimerID = timer.id
            return ringingIslandAlertConfiguration()
        }

        if let activity = activity(for: timer.id) {
            // Do **not** `end` + replace here: ending immediately after `update`/`AlertConfiguration`
            // cancels the system’s expanded-island alert before it appears (bad UX vs Clock).
            await activity.update(ringingContent, alertConfiguration: takeRingingIslandAlertIfNeeded())
            return
        }

        // No Live Activity yet (alarm with no LA, or Activities were cleared): standard request, then alert update.
        let attributes = TimerActivityAttributes(timerID: timer.id.uuidString, doodleImageData: imageData)
        do {
            if #available(iOS 18.0, *) {
                _ = try Activity<TimerActivityAttributes>.request(
                    attributes: attributes,
                    content: ringingContent,
                    pushType: nil,
                    style: .standard
                )
            } else {
                _ = try Activity<TimerActivityAttributes>.request(
                    attributes: attributes,
                    content: ringingContent,
                    pushType: nil
                )
            }
        } catch {
            print("Live Activity request (ringing) failed: \(error)")
            return
        }
        guard let created = activity(for: timer.id) else { return }
        await created.update(ringingContent, alertConfiguration: takeRingingIslandAlertIfNeeded())
    }

    private func updateOrRequestPrimary(_ timer: DrawnTimer) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let imageData = thumbnailJPEGForActivityAttributes(from: timer)
        let state = contentState(from: timer)
        // `staleDate` = countdown fire time; avoid churning **`activity.update()`** during a steady run (**`Text(timerInterval:)` is self-updating).
        let stale = primaryStaleDate(forPrimaryRunning: state)
        let primaryContent = ActivityContent(state: state, staleDate: stale)

        if let activity = activity(for: timer.id) {
            await activity.update(primaryContent)
        } else {
            guard UIApplication.shared.applicationState == .active else { return }
            let attributes = TimerActivityAttributes(timerID: timer.id.uuidString, doodleImageData: imageData)
            do {
                if #available(iOS 18.0, *) {
                    _ = try Activity<TimerActivityAttributes>.request(
                        attributes: attributes,
                        content: primaryContent,
                        pushType: nil,
                        style: .standard
                    )
                } else {
                    _ = try Activity<TimerActivityAttributes>.request(
                        attributes: attributes,
                        content: primaryContent,
                        pushType: nil
                    )
                }
            } catch {
                print("Live Activity request (primary) failed: \(error)")
            }
        }
    }

    private func endActivitiesAsync(where shouldEnd: (UUID) -> Bool) async {
        for a in Activity<TimerActivityAttributes>.activities {
            guard let id = UUID(uuidString: a.attributes.timerID) else { continue }
            guard shouldEnd(id) else { continue }
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func endAllActivitiesAsync() async {
        for a in Activity<TimerActivityAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Deep-link controls can momentarily foreground the app, then suspend quickly. Keep reconcile alive
    /// long enough to push ActivityKit updates (especially pause) before suspension.
    private func beginReconcileBackgroundTaskIfNeeded() -> UIBackgroundTaskIdentifier {
        if UIApplication.shared.applicationState == .active {
            return .invalid
        }
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "LiveActivityReconcile") { [weak self] in
            guard let self else { return }
            if self.reconcileBackgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.reconcileBackgroundTask)
                self.reconcileBackgroundTask = .invalid
            }
        }
        reconcileBackgroundTask = taskID
        return taskID
    }

    private func endReconcileBackgroundTask(_ taskID: UIBackgroundTaskIdentifier) {
        guard taskID != .invalid else { return }
        guard taskID == reconcileBackgroundTask else {
            UIApplication.shared.endBackgroundTask(taskID)
            return
        }
        UIApplication.shared.endBackgroundTask(taskID)
        reconcileBackgroundTask = .invalid
    }

    private func contentState(from timer: DrawnTimer) -> TimerActivityAttributes.ContentState {
        let isPaused = timer.hasStarted && !timer.isRunning
        let endDate: Date
        if isPaused {
            endDate = Date()
        } else if timer.isRunning {
            endDate = Date().addingTimeInterval(TimeInterval(timer.remainingSeconds))
        } else {
            endDate = Date()
        }
        // Do **not** embed doodle JPEG in ContentState — keep payload tiny; widgets use `state.doodleImageData ?? attributes.doodleImageData`.
        // Prefer **few** pushes: running countdown relies on **`endDate`** + widget **`Text(timerInterval:)`**,
        // not periodic `activity.update()` from the app (`reconcileLiveActivity()` only on interactions / ringing / foreground alignment).
        return TimerActivityAttributes.ContentState(
            name: timer.name,
            endDate: endDate,
            isPaused: isPaused,
            remainingSeconds: timer.remainingSeconds,
            totalSeconds: timer.duration.totalSeconds,
            doodleImageData: nil,
            isRinging: false,
            contentPushEpoch: nextContentPushEpochValue()
        )
    }

    private func ringingContentState(from timer: DrawnTimer) -> TimerActivityAttributes.ContentState {
        TimerActivityAttributes.ContentState(
            name: timer.name,
            endDate: Date(),
            isPaused: false,
            remainingSeconds: 0,
            totalSeconds: timer.duration.totalSeconds,
            doodleImageData: nil,
            isRinging: true,
            contentPushEpoch: nextContentPushEpochValue()
        )
    }

    private func activity(for timerID: UUID) -> Activity<TimerActivityAttributes>? {
        Activity<TimerActivityAttributes>.activities
            .first { $0.attributes.timerID == timerID.uuidString }
    }

    /// When the countdown is active, ActivityKit treats `endDate` as the invalidation milestone (Claude/`staleDate` guidance).
    private func primaryStaleDate(forPrimaryRunning state: TimerActivityAttributes.ContentState) -> Date? {
        guard !state.isRinging else { return nil }
        guard !state.isPaused, state.remainingSeconds > 0 else { return nil }
        return state.endDate
    }

    /// Full-res thumbnail render (cached). Use `thumbnailJPEGForActivityAttributes` for ActivityKit-sized bytes.
    private func doodleImageDataForContentStore(from timer: DrawnTimer) -> Data? {
        guard let doodleData = timer.doodleData else {
            doodleRenderCache.removeValue(forKey: timer.id.uuidString)
            return nil
        }
        let key = timer.id.uuidString
        let byteHash = doodleData.hashValue
        if let entry = doodleRenderCache[key],
           entry.hash == byteHash,
           entry.ver == doodleRasterVersion {
            return entry.data
        }
        let data = renderedDoodleData(from: doodleData)
        doodleRenderCache[key] = (byteHash, doodleRasterVersion, data)
        return data
    }

    /// Keep JPEG **well under** ActivityKit’s ~4 KB effective budget (Codable / transport overhead inflates payload).
    private let liveActivityJPEGMaxBytes = 2_400

    /// Raster + clamp — **never** return an oversized JPEG; `nil` drops the doodle but keeps the Live Activity working.
    private func thumbnailJPEGForActivityAttributes(from timer: DrawnTimer) -> Data? {
        guard let data = doodleImageDataForContentStore(from: timer),
              let image = UIImage(data: data)
        else { return nil }
        return jpegCompressedToFitLiveActivity(image, maxBytes: liveActivityJPEGMaxBytes)
    }

    private func jpegCompressedToFitLiveActivity(_ image: UIImage, maxBytes: Int) -> Data? {
        var img = image.flattenedOnOpaqueWhite()

        for _ in 0..<48 {
            var q: CGFloat = 0.88
            while q >= 0.08 {
                if let d = img.jpegData(compressionQuality: q), d.count <= maxBytes { return d }
                q -= 0.045
            }
            let newW = img.size.width * 0.72
            let newH = img.size.height * 0.72
            guard newW >= 18, newH >= 18 else { break }
            img = UIImage.resampledOnOpaqueWhite(img, boundsSize: CGSize(width: newW, height: newH))
        }

        guard let fallback = img.jpegData(compressionQuality: 0.22), fallback.count <= maxBytes else {
            print("Live Activity doodle JPEG could not fit under \(maxBytes) bytes; omitting thumbnail")
            return nil
        }
        return fallback
    }

    /// Renders ink on the **full doodle canvas** (same `337×337` pt bounds as create/edit and home cards), not stroke-bounds crop.
    private func renderedDoodleData(from doodleData: Data) -> Data? {
        guard let drawing = try? PKDrawing(data: doodleData) else { return nil }
        let strokeBounds = drawing.bounds
        guard strokeBounds.width > 0.5, strokeBounds.height > 0.5 else { return nil }

        let canvasSide: CGFloat = 337
        let fullCanvas = CGRect(origin: .zero, size: CGSize(width: canvasSide, height: canvasSide))

        let scale: CGFloat = 2
        let raw = drawing.image(from: fullCanvas, scale: scale)
        /// Point size caps pixels so the first JPEG isn’t huge before `jpegCompressed…` runs.
        let maxSidePoints: CGFloat = 64
        let w = raw.size.width
        let h = raw.size.height
        let m = max(w, h)
        guard m > 0 else { return nil }
        let downscale = min(1, maxSidePoints / m)
        let finalImage: UIImage
        if downscale < 1 - 0.001 {
            let newSize = CGSize(width: w * downscale, height: h * downscale)
            let format = UIGraphicsImageRendererFormat()
            format.opaque = true
            format.scale = raw.scale
            let r = UIGraphicsImageRenderer(size: newSize, format: format)
            finalImage = r.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: newSize))
                raw.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            finalImage = raw
        }
        // PKDrawing `image(from:)` is usually transparent; `jpegData` composites onto black otherwise → black thumbnails.
        let opaque = finalImage.flattenedOnOpaqueWhite()
        return opaque.jpegData(compressionQuality: 0.88)
    }
}

private extension UIImage {
    /// Premultiplied onto white so `jpegData` does not produce a black placeholder.
    func flattenedOnOpaqueWhite() -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.opaque = true
        fmt.scale = scale
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Bounds size is in **points** (UIKit image coordinate space).
    static func resampledOnOpaqueWhite(_ image: UIImage, boundsSize: CGSize) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.opaque = true
        fmt.scale = image.scale
        let r = UIGraphicsImageRenderer(size: boundsSize, format: fmt)
        return r.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: boundsSize))
            image.draw(in: CGRect(origin: .zero, size: boundsSize))
        }
    }
}
