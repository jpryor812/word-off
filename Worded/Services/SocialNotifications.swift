import Foundation
@preconcurrency import UserNotifications

/// Local notifications for friend challenges and friend requests while backgrounded.
/// (True APNs push is a follow-up; this covers “left the app mid-poll” cases.)
@MainActor
enum SocialNotifications {
    private static let challengeId = "worded.social.challenge"
    private static let friendRequestId = "worded.social.friendRequest"

    static func postChallenge(from username: String) {
        guard SettingsStore.shared.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Game challenge!"
        content.body = "\(username) challenged you to a Worded match."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(challengeId).\(UUID().uuidString)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func postFriendRequest(from username: String) {
        guard SettingsStore.shared.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Friend request"
        content.body = "\(username) wants to be friends on Worded."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(friendRequestId).\(UUID().uuidString)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
