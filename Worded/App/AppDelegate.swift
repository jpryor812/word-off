import UIKit
import UserNotifications

/// Bridges APNs device-token callbacks into SwiftUI.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushRegistration.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Simulator / missing capability — local notifications still work.
        #if DEBUG
        print("APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    // Show banners while the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run {
            PushNotificationRouter.handle(userInfo: userInfo)
        }
    }
}

/// Routes tapped push payloads into AppState deep-link handlers.
@MainActor
enum PushNotificationRouter {
    static weak var app: AppState?

    static func handle(userInfo: [AnyHashable: Any]) {
        guard let app else { return }
        if let challengeId = userInfo["challenge_id"] as? String, !challengeId.isEmpty {
            Task { await app.openChallengeFromNotification(challengeId: challengeId) }
            return
        }
        if let type = userInfo["type"] as? String, type == "friend_request" {
            Task { await app.friendsService.refresh() }
        }
    }
}
