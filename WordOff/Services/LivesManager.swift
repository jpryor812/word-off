import Foundation
import SwiftUI

/// Lives, login streaks, and per-day counters. All limits reset at local midnight.
///
/// Rules:
/// - 5 base lives/day for free users (each PvP game costs 1).
/// - +1 bonus life per 2 consecutive login days (max +5 at a 10-day streak).
/// - Streak break resets bonus lives to 0.
/// - First friend game each day is free (doesn't consume a life).
/// - Premium / daily pass: unlimited PvP, no life tracking.
/// - Daily puzzles never consume lives; free users pick 3 of the daily sizes.
@MainActor
final class LivesManager: ObservableObject {
    @AppStorage("wordoff.lives.day") private var currentDay = ""
    @AppStorage("wordoff.lives.used") private var livesUsedToday = 0
    @AppStorage("wordoff.streak.count") private var streakDays = 0
    @AppStorage("wordoff.streak.lastLogin") private var lastLoginDay = ""
    @AppStorage("wordoff.friendGameUsed") private var friendGameUsedToday = false
    @AppStorage("wordoff.daily.unlocked") private var unlockedDailySizesRaw = ""

    @Published private(set) var refreshToken = 0   // bumps to trigger view updates

    private static func dayString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    /// Call at app launch. Advances streak and rolls daily counters.
    func registerLogin() {
        let today = Self.dayString()
        if lastLoginDay != today {
            if let last = dayDate(lastLoginDay),
               let todayDate = dayDate(today),
               Calendar.current.dateComponents([.day], from: last, to: todayDate).day == 1 {
                streakDays += 1
            } else {
                streakDays = 1
            }
            lastLoginDay = today
        }
        rollDayIfNeeded()
    }

    private func dayDate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: string)
    }

    private func rollDayIfNeeded() {
        let today = Self.dayString()
        if currentDay != today {
            currentDay = today
            livesUsedToday = 0
            friendGameUsedToday = false
            unlockedDailySizesRaw = ""
            refreshToken += 1
        }
    }

    var bonusLives: Int {
        min(GameConstants.maxStreakBonusLives, streakDays / 2)
    }

    var totalLivesToday: Int {
        GameConstants.baseLivesPerDay + bonusLives
    }

    var livesRemaining: Int {
        rollDayIfNeeded()
        return max(0, totalLivesToday - livesUsedToday)
    }

    var loginStreak: Int { streakDays }
    var hasFreeFriendGame: Bool {
        rollDayIfNeeded()
        return !friendGameUsedToday
    }

    /// Attempts to start a PvP game. Returns false if out of lives.
    /// Premium players should bypass this entirely.
    func consumeLife(isFriendGame: Bool = false) -> Bool {
        rollDayIfNeeded()
        if isFriendGame && !friendGameUsedToday {
            friendGameUsedToday = true
            refreshToken += 1
            return true
        }
        guard livesRemaining > 0 else { return false }
        livesUsedToday += 1
        refreshToken += 1
        return true
    }

    // MARK: - Daily puzzle picks (free users choose 3 of 5)

    var unlockedDailySizes: [Int] {
        rollDayIfNeeded()
        return unlockedDailySizesRaw.split(separator: ",").compactMap { Int($0) }
    }

    /// Free users lock in a size when they start it, up to 3 per day.
    func unlockDailySize(_ size: Int, isPremium: Bool) -> Bool {
        rollDayIfNeeded()
        if isPremium { return true }
        var sizes = unlockedDailySizes
        if sizes.contains(size) { return true }
        guard sizes.count < GameConstants.freeDailyPuzzlesPerDay else { return false }
        sizes.append(size)
        unlockedDailySizesRaw = sizes.map(String.init).joined(separator: ",")
        refreshToken += 1
        return true
    }
}
