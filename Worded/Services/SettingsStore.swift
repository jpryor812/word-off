import Foundation
import Combine

/// User preferences for notifications, sound, and haptics.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Keys {
        static let notifications = "worded.settings.notificationsEnabled"
        static let someoneWaiting = "worded.settings.notifySomeoneWaiting"
        static let maxSomeoneWaiting = "worded.settings.maxSomeoneWaitingPerDay"
        static let someoneWaitingDay = "worded.settings.someoneWaitingPingDay"
        static let someoneWaitingCount = "worded.settings.someoneWaitingPingCount"
        static let didPromptMatchmakingNotify = "worded.settings.didPromptMatchmakingNotify"
        static let didExplainOnlineRules = "worded.settings.didExplainOnlineRules"
        static let sounds = "worded.settings.soundsEnabled"
        static let haptics = "worded.settings.hapticsEnabled"
    }

    /// Master switch — only becomes true after the player grants (or re-enables) notifications.
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notifications)
            if !notificationsEnabled, notifyWhenSomeoneWaiting {
                notifyWhenSomeoneWaiting = false
            }
        }
    }

    /// Opt-in: ping when another player is waiting in the Quick Match queue.
    @Published var notifyWhenSomeoneWaiting: Bool {
        didSet { UserDefaults.standard.set(notifyWhenSomeoneWaiting, forKey: Keys.someoneWaiting) }
    }

    /// Cap on “someone’s looking” pings per local day (1…10).
    @Published var maxSomeoneWaitingPerDay: Int {
        didSet {
            let clamped = min(10, max(1, maxSomeoneWaitingPerDay))
            if clamped != maxSomeoneWaitingPerDay {
                maxSomeoneWaitingPerDay = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.maxSomeoneWaiting)
        }
    }

    @Published var soundsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundsEnabled, forKey: Keys.sounds)
            applyAudioFeedbackFlags()
        }
    }

    @Published var hapticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: Keys.haptics)
            applyAudioFeedbackFlags()
        }
    }

    /// Whether we've already shown the “search can take a minute” + OS prompt flow.
    var didPromptMatchmakingNotify: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.didPromptMatchmakingNotify) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.didPromptMatchmakingNotify) }
    }

    /// Whether we've shown the first-time online rules card (8 letters, one submit, speed bonus).
    var didExplainOnlineRules: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.didExplainOnlineRules) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.didExplainOnlineRules) }
    }

    init() {
        let defaults = UserDefaults.standard
        // Default off until the first Play Online permission flow (or Settings toggle).
        if defaults.object(forKey: Keys.notifications) == nil {
            notificationsEnabled = false
        } else {
            notificationsEnabled = defaults.bool(forKey: Keys.notifications)
        }
        notifyWhenSomeoneWaiting = defaults.bool(forKey: Keys.someoneWaiting)
        let storedMax = defaults.object(forKey: Keys.maxSomeoneWaiting) as? Int ?? 3
        maxSomeoneWaitingPerDay = min(10, max(1, storedMax))
        soundsEnabled = defaults.object(forKey: Keys.sounds) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        applyAudioFeedbackFlags()
    }

    func canSendSomeoneWaitingPing(now: Date = Date()) -> Bool {
        guard notificationsEnabled, notifyWhenSomeoneWaiting else { return false }
        let today = DailySeed.todayString(now)
        let defaults = UserDefaults.standard
        let day = defaults.string(forKey: Keys.someoneWaitingDay)
        let count = day == today ? defaults.integer(forKey: Keys.someoneWaitingCount) : 0
        return count < maxSomeoneWaitingPerDay
    }

    func markSomeoneWaitingPingSent(at date: Date = Date()) {
        let today = DailySeed.todayString(date)
        let defaults = UserDefaults.standard
        let day = defaults.string(forKey: Keys.someoneWaitingDay)
        let count = day == today ? defaults.integer(forKey: Keys.someoneWaitingCount) : 0
        defaults.set(today, forKey: Keys.someoneWaitingDay)
        defaults.set(count + 1, forKey: Keys.someoneWaitingCount)
    }

    private func applyAudioFeedbackFlags() {
        SoundPlayer.shared.isEnabled = soundsEnabled
        Haptics.shared.isEnabled = hapticsEnabled
    }
}
