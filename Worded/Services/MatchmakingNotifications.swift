import Foundation
@preconcurrency import UserNotifications
import UIKit

enum MatchmakingNotificationID {
    static let matchFound = "worded.matchmaking.matchFound"
    static let aiReady = "worded.matchmaking.aiReady"
    static let searchPaused = "worded.matchmaking.searchPaused"
    static let searchTimeout = "worded.matchmaking.searchTimeout"
    static let someoneWaiting = "worded.matchmaking.someoneWaiting"
    static let categoryPlay = "WORD_ED_MATCH_FOUND"
}

/// Local notifications for quick-match while the app is backgrounded.
/// Note: these only fire if the process is still awake (or we pre-scheduled them).
/// A true "opponent found hours later" alert needs remote push from the server.
@MainActor
enum MatchmakingNotifications {
    private static var didRegisterCategories = false

    static func requestAuthorizationIfNeeded() async {
        registerCategoriesIfNeeded()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            SettingsStore.shared.notificationsEnabled = true
            await PushRegistration.requestAuthorizationAndRegister()
        }
    }

    /// Returns whether we can currently deliver banners/alerts.
    static func canNotify() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Prompt if not determined; open iOS Settings if previously denied.
    static func requestOrOpenSettingsIfDenied() async {
        let status = await authorizationStatus()
        switch status {
        case .notDetermined:
            await requestAuthorizationIfNeeded()
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        case .authorized, .provisional, .ephemeral:
            SettingsStore.shared.notificationsEnabled = true
            await PushRegistration.requestAuthorizationAndRegister()
        @unknown default:
            break
        }
    }

    static func postMatchFound(opponentName: String) {
        clearSearchTimeout()
        post(
            id: MatchmakingNotificationID.matchFound,
            title: "Match found!",
            body: "You're up against \(opponentName). Tap to play.")
    }

    /// Fired when iOS is about to suspend us mid-search.
    static func postSearchPaused() {
        post(
            id: MatchmakingNotificationID.searchPaused,
            title: "Still searching…",
            body: "Reopen Worded to keep looking for a match.")
    }

    /// Opt-in alert when another player is waiting for Quick Match.
    static func postSomeoneWaiting() {
        guard SettingsStore.shared.notificationsEnabled,
              SettingsStore.shared.notifyWhenSomeoneWaiting else { return }
        post(
            id: MatchmakingNotificationID.someoneWaiting,
            title: "Someone’s looking for a match",
            body: "A player is waiting for Quick Match — jump in and play!")
    }

    static func clearSearchTimeout() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: [MatchmakingNotificationID.searchTimeout])
        center.removeDeliveredNotifications(
            withIdentifiers: [MatchmakingNotificationID.searchTimeout])
    }

    static func clearMatchFound() {
        let center = UNUserNotificationCenter.current()
        let ids = [
            MatchmakingNotificationID.matchFound,
            MatchmakingNotificationID.aiReady,
            MatchmakingNotificationID.searchPaused,
            MatchmakingNotificationID.searchTimeout,
            MatchmakingNotificationID.someoneWaiting,
        ]
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func post(id: String, title: String, body: String) {
        registerCategoriesIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = MatchmakingNotificationID.categoryPlay

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func registerCategoriesIfNeeded() {
        guard !didRegisterCategories else { return }
        didRegisterCategories = true
        let play = UNNotificationCategory(
            identifier: MatchmakingNotificationID.categoryPlay,
            actions: [],
            intentIdentifiers: [],
            options: [])
        UNUserNotificationCenter.current().setNotificationCategories([play])
    }
}
