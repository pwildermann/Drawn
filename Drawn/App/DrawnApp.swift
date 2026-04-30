import SwiftUI

@main
struct DrawnApp: App {
    @UIApplicationDelegateAdaptor(DrawnAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
