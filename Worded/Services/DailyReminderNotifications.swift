import Foundation
@preconcurrency import UserNotifications

enum DailyReminderNotificationID {
    static let evening = "worded.daily.eveningReminder"
}

/// Local 8:00pm reminder when the player hasn't completed any daily yet today.
@MainActor
enum DailyReminderNotifications {
    /// Reschedule the next 8pm ping. Skips tonight if they've already played a daily.
    static func refresh(hasPlayedAnyDailyToday: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [DailyReminderNotificationID.evening])
        center.removeDeliveredNotifications(withIdentifiers: [DailyReminderNotificationID.evening])

        guard SettingsStore.shared.notificationsEnabled else { return }

        // Never prompt here — permission is requested from the Play Online flow / Settings.
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        guard let fireDate = nextEightPM(skipToday: hasPlayedAnyDailyToday) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Don’t leave points on the table!"
        content.body = "Clear today’s daily challenges and climb the leaderboard."
        content.sound = .default

        var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        comps.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: DailyReminderNotificationID.evening,
            content: content,
            trigger: trigger)
        try? await center.add(request)
    }

    /// Next 8:00pm local. If `skipToday`, always use tomorrow (or later).
    private static func nextEightPM(skipToday: Bool) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = 20
        comps.minute = 0
        comps.second = 0
        guard var candidate = calendar.date(from: comps) else { return nil }

        if skipToday || candidate <= now {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }
}
