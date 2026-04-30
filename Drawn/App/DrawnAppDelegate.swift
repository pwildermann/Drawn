import UIKit
import UserNotifications

extension Notification.Name {
    /// `UIOpenURLContext` delivery from `scene(_:openURLContexts:)` — covers foreground cases SwiftUI `onOpenURL` can miss.
    static let drawnAppDelegateOpenURL = Notification.Name("Drawn.drawnAppDelegateOpenURL")
}

final class DrawnSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            NotificationCenter.default.post(
                name: .drawnAppDelegateOpenURL,
                object: nil,
                userInfo: ["url": context.url]
            )
        }
    }
}

final class DrawnAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// While Drawn is **foreground**, only **play** the completion sound (no in-app banner). Outside the app, iOS shows the standard alert per user settings.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.sound])
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let base = connectingSceneSession.configuration
        let config = UISceneConfiguration(name: base.name ?? "Default Configuration", sessionRole: base.role)
        config.sceneClass = base.sceneClass
        config.delegateClass = DrawnSceneDelegate.self
        return config
    }
}
