import Foundation
import Combine

/// User preferences for notifications, sound, and haptics.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Keys {
        static let notifications = "worded.settings.notificationsEnabled"
        static let someoneWaiting = "worded.settings.notifySomeoneWaiting"
        static let sounds = "worded.settings.soundsEnabled"
        static let haptics = "worded.settings.hapticsEnabled"
        static let lastSomeoneWaitingPing = "worded.settings.lastSomeoneWaitingPingAt"
    }

    /// Master switch for daily reminders and optional alerts.
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

    /// Minimum gap between "someone waiting" local notifications.
    static let someoneWaitingCooldown: TimeInterval = 60 * 60

    init() {
        let defaults = UserDefaults.standard
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        notifyWhenSomeoneWaiting = defaults.bool(forKey: Keys.someoneWaiting)
        soundsEnabled = defaults.object(forKey: Keys.sounds) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        applyAudioFeedbackFlags()
    }

    func canSendSomeoneWaitingPing(now: Date = Date()) -> Bool {
        guard notificationsEnabled, notifyWhenSomeoneWaiting else { return false }
        let last = UserDefaults.standard.object(forKey: Keys.lastSomeoneWaitingPing) as? Date
        guard let last else { return true }
        return now.timeIntervalSince(last) >= Self.someoneWaitingCooldown
    }

    func markSomeoneWaitingPingSent(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: Keys.lastSomeoneWaitingPing)
    }

    private func applyAudioFeedbackFlags() {
        SoundPlayer.shared.isEnabled = soundsEnabled
        Haptics.shared.isEnabled = hapticsEnabled
    }
}
