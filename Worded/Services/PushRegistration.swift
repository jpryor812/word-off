import Foundation
import UIKit
import UserNotifications

/// Registers for remote APNs and upserts the device token to Supabase.
@MainActor
enum PushRegistration {
    private static let tokenKey = "worded.push.deviceToken"

    static var currentTokenHex: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    static func requestAuthorizationAndRegister() async {
        guard SettingsStore.shared.notificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        case .denied:
            return
        default:
            break
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func handleDeviceToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        Task { await upsertToken(hex) }
    }

    static func syncStoredTokenIfNeeded() async {
        guard SettingsStore.shared.notificationsEnabled else { return }
        if let hex = currentTokenHex {
            await upsertToken(hex)
            return
        }
        // Don't prompt from bootstrap — only re-register if already authorized.
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    static func clearTokenFromServer() async {
        guard let hex = currentTokenHex,
              let userId = SupabaseClient.shared.currentSession?.userId else { return }
        _ = try? await SupabaseClient.shared.request(
            table: "device_tokens",
            method: "DELETE",
            query: "user_id=eq.\(userId)&token=eq.\(hex)")
    }

    private static func upsertToken(_ hex: String) async {
        guard SettingsStore.shared.notificationsEnabled else { return }
        guard SupabaseConfig.isConfigured,
              let userId = SupabaseClient.shared.currentSession?.userId,
              userId != "local" else { return }

        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif

        let payload: [String: Any] = [
            "user_id": userId,
            "token": hex,
            "platform": "ios",
            "environment": environment,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        _ = try? await SupabaseClient.shared.request(
            table: "device_tokens",
            method: "POST",
            body: body,
            prefer: "resolution=merge-duplicates")
    }
}

/// Notifies a user via the Supabase Edge Function (APNs).
enum PushNotify {
    static func challenge(toUserId: String, fromUsername: String, challengeId: String) async {
        await invoke(
            type: "challenge",
            toUserId: toUserId,
            title: "Game challenge!",
            body: "\(fromUsername) challenged you to a Worded match.",
            data: ["challenge_id": challengeId, "type": "challenge"])
    }

    static func friendRequest(toUserId: String, fromUsername: String) async {
        await invoke(
            type: "friend_request",
            toUserId: toUserId,
            title: "Friend request",
            body: "\(fromUsername) wants to be friends on Worded.",
            data: ["type": "friend_request"])
    }

    private static func invoke(
        type: String,
        toUserId: String,
        title: String,
        body: String,
        data: [String: String]
    ) async {
        guard SupabaseConfig.isConfigured,
              SupabaseClient.shared.currentSession != nil else { return }
        _ = try? await SupabaseClient.shared.invokeFunction(
            name: "send-push",
            body: [
                "type": type,
                "to_user_id": toUserId,
                "title": title,
                "body": body,
                "data": data,
            ])
    }
}
