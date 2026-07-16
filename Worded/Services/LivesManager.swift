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
/// - Daily puzzles never consume lives; all sizes are free to play.
@MainActor
final class LivesManager: ObservableObject {
    @AppStorage("worded.lives.day") private var currentDay = ""
    @AppStorage("worded.lives.used") private var livesUsedToday = 0
    @AppStorage("worded.streak.count") private var streakDays = 0
    @AppStorage("worded.streak.lastLogin") private var lastLoginDay = ""
    @AppStorage("worded.friendGameUsed") private var friendGameUsedToday = false
    @AppStorage("worded.daily.unlocked") private var unlockedDailySizesRaw = ""
    @AppStorage("worded.daily.streak.count") private var dailyStreakDays = 0
    @AppStorage("worded.daily.streak.lastDay") private var lastDailyCompletionDay = ""

    @Published private(set) var refreshToken = 0   // bumps to trigger view updates
    /// Set by the most recent `consumeLife` call — true only when a daily life was spent.
    private(set) var didDeductLifeOnLastConsume = false

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
        refreshDailyStreakIfStale()
    }

    /// Consecutive local-time days with at least one daily puzzle completed.
    var dailyCompletionStreak: Int { dailyStreakDays }

    /// Call when a daily puzzle is finished. Extends the streak on the first
    /// completion of each local-time day.
    func recordDailyCompletion(day: String) {
        if lastDailyCompletionDay == day {
            refreshToken += 1
            return
        }
        if lastDailyCompletionDay.isEmpty {
            dailyStreakDays = 1
        } else if isPreviousUTCDay(lastDailyCompletionDay, before: day) {
            dailyStreakDays += 1
        } else {
            dailyStreakDays = 1
        }
        lastDailyCompletionDay = day
        refreshToken += 1
    }

    /// Resets the daily streak if the player skipped a UTC day entirely.
    private func refreshDailyStreakIfStale() {
        let today = DailySeed.todayString()
        guard !lastDailyCompletionDay.isEmpty else { return }
        if lastDailyCompletionDay == today { return }
        if isPreviousUTCDay(lastDailyCompletionDay, before: today) { return }
        dailyStreakDays = 0
        refreshToken += 1
    }

    private func isPreviousUTCDay(_ earlier: String, before later: String) -> Bool {
        guard let earlyDate = utcDayDate(earlier),
              let lateDate = utcDayDate(later),
              let between = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: earlyDate) else {
            return false
        }
        return Calendar(identifier: .gregorian).isDate(between, inSameDayAs: lateDate)
    }

    private func utcDayDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)
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
        didDeductLifeOnLastConsume = false
        if isFriendGame && !friendGameUsedToday {
            friendGameUsedToday = true
            refreshToken += 1
            return true
        }
        guard livesRemaining > 0 else { return false }
        livesUsedToday += 1
        didDeductLifeOnLastConsume = true
        refreshToken += 1
        return true
    }

    // MARK: - Daily puzzle access

    var unlockedDailySizes: [Int] {
        rollDayIfNeeded()
        return unlockedDailySizesRaw.split(separator: ",").compactMap { Int($0) }
    }

    func unlockDailySize(_ size: Int, isPremium: Bool) -> Bool {
        true
    }
}
