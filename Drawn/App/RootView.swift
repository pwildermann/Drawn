import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var timerStore = TimerStore()

    var body: some View {
        HomeView()
            .environmentObject(timerStore)
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
        let host = (url.host ?? "").lowercased()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let id = components?
            .queryItems?
            .first { $0.name.lowercased() == "id" }?
            .value
            .flatMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let id else { return }
        switch host {
        case "stop":
            timerStore.resetTimer(id)
        case "toggle":
            timerStore.toggleTimer(id)
        default:
            break
        }
    }
}

#Preview {
    RootView()
}
