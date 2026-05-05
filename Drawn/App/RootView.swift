import DrawnTimerEngine
import OSLog
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var timerStore = TimerStore()
    @State private var lastHandledDrawnActionSignature: String?
    @State private var lastHandledDrawnActionAt: Date = .distantPast

    var body: some View {
        HomeView()
            .environment(timerStore)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    timerStore.drainPendingExtensionIntents()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                timerStore.drainPendingExtensionIntents()
            }
            .onOpenURL(perform: handleDrawnURL(_:))
            .onReceive(NotificationCenter.default.publisher(for: .drawnAppDelegateOpenURL)) { note in
                if let url = note.userInfo?["url"] as? URL {
                    handleDrawnURL(url)
                }
            }
            .task {
                await DrawnNotificationPermissionEducation.skipPrimerWhenAuthorizationAlreadyResolved()
            }
    }

    /// `drawn://stop|toggle?id=` from Live Activity `Link`s, Shortcuts, etc. Host/scheme casing can vary by source.
    private func handleDrawnURL(_ url: URL) {
        guard url.scheme?.caseInsensitiveCompare("drawn") == .orderedSame else { return }
        let route: String = {
            let host = (url.host ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !host.isEmpty { return host }

            let trimmedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !trimmedPath.isEmpty { return trimmedPath }

            // Handles opaque forms like `drawn:toggle?id=...` where host/path can be empty.
            let raw = url.absoluteString
            let afterScheme = raw.replacingOccurrences(of: #"^drawn:"#, with: "", options: .regularExpression)
            let opaque = afterScheme
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let token = opaque.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: true).first
            return token.map { String($0).lowercased() } ?? ""
        }()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let id = components?
            .queryItems?
            .first { $0.name.lowercased() == "id" }?
            .value
            .flatMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        DrawnLog.liveActivity.debug("URL route=\(route, privacy: .public) raw=\(url.absoluteString, privacy: .public) parsedID=\(String(describing: id), privacy: .public)")
        guard let id else { return }
        let signature = "\(route)|\(id.uuidString)"
        let now = Date()
        if signature == lastHandledDrawnActionSignature,
           now.timeIntervalSince(lastHandledDrawnActionAt) < 0.6 {
            DrawnLog.liveActivity.debug("URL deduped signature=\(signature, privacy: .public)")
            return
        }
        lastHandledDrawnActionSignature = signature
        lastHandledDrawnActionAt = now
        guard let controlRoute = LiveActivityControlRoute(token: route) else { return }
        switch controlRoute {
        case .stop:
            // Discard stale queued actions so foreground drain cannot replay contradictory events.
            _ = PendingIntentBridge.consumePendingStop()
            _ = PendingIntentBridge.dequeueAllPendingToggleUUIDs()
            timerStore.resetTimer(id)
        case .pause:
            _ = PendingIntentBridge.dequeueAllPendingToggleUUIDs()
            timerStore.setTimerRunning(id, running: false)
        case .resume:
            _ = PendingIntentBridge.dequeueAllPendingToggleUUIDs()
            timerStore.setTimerRunning(id, running: true)
        case .toggle:
            // Backward-compat route used by older widget builds.
            // Deep-link toggle is authoritative. Clear queued toggles first to avoid double-toggle no-op.
            _ = PendingIntentBridge.dequeueAllPendingToggleUUIDs()
            timerStore.toggleTimer(id)
        }
    }
}

#Preview {
    RootView()
}
