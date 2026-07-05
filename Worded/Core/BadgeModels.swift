import Foundation
import SwiftUI

/// Persistent counters that drive badge tiers. Stored locally and synced to
/// Supabase `profiles.badge_stats` so opponents can see featured badges.
struct BadgeStats: Codable, Equatable {
    var dailyMaxWordHits = 0
    var pvpMaxWordHits = 0
    var speedBonusCount = 0
    var pvpWins = 0
    /// Best daily percentile tier achieved: 0 = none, else 25 / 10 / 5 / 1.
    var dailyPercentileBest = 0
    var flawlessDailyCount = 0
    var cleanSweepCount = 0
    var fullMenuDailyCount = 0
    var loginStreakBest = 0
    var dailyStreakBest = 0
    /// Most PvP wins in a single calendar day (local time).
    var pvpDailyWinsBest = 0
    /// Longest consecutive PvP match win streak.
    var pvpWinStreakBest = 0
    /// Wins in a match that went the full 7 rounds (4–3).
    var game7Count = 0

    enum CodingKeys: String, CodingKey {
        case dailyMaxWordHits = "daily_max_word"
        case pvpMaxWordHits = "pvp_max_word"
        case speedBonusCount = "speed_bonus"
        case pvpWins = "pvp_wins"
        case dailyPercentileBest = "daily_percentile_best"
        case flawlessDailyCount = "flawless_daily"
        case cleanSweepCount = "clean_sweep"
        case fullMenuDailyCount = "full_menu_daily"
        case loginStreakBest = "login_streak_best"
        case dailyStreakBest = "daily_streak_best"
        case pvpDailyWinsBest = "pvp_daily_wins_best"
        case pvpWinStreakBest = "pvp_win_streak_best"
        case game7Count = "game7"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyMaxWordHits = try c.decodeIfPresent(Int.self, forKey: .dailyMaxWordHits) ?? 0
        pvpMaxWordHits = try c.decodeIfPresent(Int.self, forKey: .pvpMaxWordHits) ?? 0
        speedBonusCount = try c.decodeIfPresent(Int.self, forKey: .speedBonusCount) ?? 0
        pvpWins = try c.decodeIfPresent(Int.self, forKey: .pvpWins) ?? 0
        dailyPercentileBest = try c.decodeIfPresent(Int.self, forKey: .dailyPercentileBest) ?? 0
        flawlessDailyCount = try c.decodeIfPresent(Int.self, forKey: .flawlessDailyCount) ?? 0
        cleanSweepCount = try c.decodeIfPresent(Int.self, forKey: .cleanSweepCount) ?? 0
        fullMenuDailyCount = try c.decodeIfPresent(Int.self, forKey: .fullMenuDailyCount) ?? 0
        loginStreakBest = try c.decodeIfPresent(Int.self, forKey: .loginStreakBest) ?? 0
        dailyStreakBest = try c.decodeIfPresent(Int.self, forKey: .dailyStreakBest) ?? 0
        pvpDailyWinsBest = try c.decodeIfPresent(Int.self, forKey: .pvpDailyWinsBest) ?? 0
        pvpWinStreakBest = try c.decodeIfPresent(Int.self, forKey: .pvpWinStreakBest) ?? 0
        game7Count = try c.decodeIfPresent(Int.self, forKey: .game7Count) ?? 0
    }
}

enum BadgeKind: String, CaseIterable, Codable {
    case dailyMaxWord
    case dailyPercentile
    case pvpMaxWord
    case speedBonus
    case pvpWins
    case loginStreak
    case dailyStreak
    case flawlessDaily
    case cleanSweep
    case fullMenuDaily
    case pvpDailyWins
    case pvpWinStreak
    case game7

    /// Count thresholds for tiered badges (1 · 5 · 10 · 25 · 100).
    static let countTiers = [1, 5, 10, 25, 100]
    /// Wins in one day → Daily Dominator badge tiers.
    static let dailyWinTiers = [1, 3, 5, 10]
    /// Consecutive match wins → Hot Streak badge tiers.
    static let winStreakTiers = [3, 5, 10, 25]
    static let loginStreakTiers = [3, 7, 10]
    static let dailyStreakTiers = [3, 7]
    static let percentileTiers = [25, 10, 5, 1]

    var detail: String {
        switch self {
        case .dailyMaxWord: return "Play the top-scoring word on a daily rack"
        case .dailyPercentile: return "Rank in the top tier on a daily puzzle"
        case .pvpMaxWord: return "Play the top-scoring word in a PvP round"
        case .speedBonus: return "Earn the speed bonus in a PvP round"
        case .pvpWins: return "Win Quick Match or friend games"
        case .loginStreak: return "Log in on consecutive days"
        case .dailyStreak: return "Complete daily puzzles on consecutive days"
        case .flawlessDaily: return "Top word on every rack in one daily"
        case .cleanSweep: return "Win every round in a match"
        case .fullMenuDaily: return "Complete every daily rack size in one day"
        case .pvpDailyWins: return "Win PvP matches in one day"
        case .pvpWinStreak: return "Win PvP matches in a row"
        case .game7: return "Win a full 7-round match (4–3)"
        }
    }

    var icon: String {
        switch self {
        case .dailyMaxWord: return "text.book.closed.fill"
        case .dailyPercentile: return "medal.fill"
        case .pvpMaxWord: return "bolt.fill"
        case .speedBonus: return "wind"
        case .pvpWins: return "crown.fill"
        case .loginStreak: return "flame.fill"
        case .dailyStreak: return "calendar"
        case .flawlessDaily: return "star.fill"
        case .cleanSweep: return "sparkles"
        case .fullMenuDaily: return "tray.full.fill"
        case .pvpDailyWins: return "sun.max.fill"
        case .pvpWinStreak: return "flame.fill"
        case .game7: return "7.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .dailyMaxWord: return "Lexicon"
        case .dailyPercentile: return "Elite Daily"
        case .pvpMaxWord: return "Arena Lexicon"
        case .speedBonus: return "Quick Draw"
        case .pvpWins: return "Champion"
        case .loginStreak: return "Regular"
        case .dailyStreak: return "Daily Grinder"
        case .flawlessDaily: return "Flawless"
        case .cleanSweep: return "Clean Sweep"
        case .fullMenuDaily: return "Full Menu"
        case .pvpDailyWins: return "Daily Dominator"
        case .pvpWinStreak: return "Hot Streak"
        case .game7: return "Game 7"
        }
    }

    /// Higher = rarer, used to pick featured badges for the pre-game border.
    var rarity: Int {
        switch self {
        case .cleanSweep: return 100
        case .game7: return 98
        case .flawlessDaily: return 95
        case .dailyPercentile: return 90
        case .pvpWinStreak: return 85
        case .fullMenuDaily: return 70
        case .pvpDailyWins: return 65
        case .pvpMaxWord: return 60
        case .dailyMaxWord: return 55
        case .pvpWins: return 50
        case .speedBonus: return 40
        case .dailyStreak: return 30
        case .loginStreak: return 20
        }
    }
}

struct BadgeProgress: Equatable {
    let kind: BadgeKind
    let current: Int
    let nextThreshold: Int

    var remaining: Int { max(0, nextThreshold - current) }

    var label: String {
        switch kind {
        case .pvpDailyWins:
            return "\(nextThreshold) wins today"
        case .pvpWinStreak:
            return "\(nextThreshold) win streak"
        case .dailyPercentile:
            return "Reach top \(nextThreshold)%"
        case .loginStreak, .dailyStreak:
            return "\(nextThreshold)-day streak"
        default:
            return kind.label
        }
    }
}

/// One row in the stats badge list — current progress toward the next tier.
struct BadgeTrackItem: Identifiable, Equatable {
    let kind: BadgeKind
    let current: Int
    let nextThreshold: Int?
    let earnedTier: Int?
    let detail: String

    var id: BadgeKind { kind }

    var progressFraction: Double {
        guard let next = nextThreshold, next > 0 else {
            return earnedTier != nil ? 1 : 0
        }
        return min(1, Double(current) / Double(next))
    }

    var isMaxed: Bool { earnedTier != nil && nextThreshold == nil }

    var progressLabel: String {
        switch kind {
        case .dailyPercentile:
            if let earned = earnedTier {
                if let next = nextThreshold {
                    return "Top \(earned)% → Top \(next)%"
                }
                return "Top \(earned)%"
            }
            if let next = nextThreshold {
                return "Next: Top \(next)%"
            }
            return "Not yet"
        case .flawlessDaily, .cleanSweep, .fullMenuDaily:
            return earnedTier != nil ? "Earned" : "Not yet"
        default:
            if let next = nextThreshold {
                return "\(current)/\(next)"
            }
            if let earned = earnedTier {
                return "Tier \(earned)"
            }
            return "Not yet"
        }
    }

    var nextTierLabel: String? {
        guard let next = nextThreshold else { return nil }
        switch kind {
        case .dailyPercentile: return "Top \(next)%"
        case .pvpDailyWins: return "\(next) wins today"
        case .pvpWinStreak: return "\(next) in a row"
        case .loginStreak, .dailyStreak: return "\(next) days"
        case .flawlessDaily, .cleanSweep, .fullMenuDaily: return "Earn once"
        default: return "Tier \(next)"
        }
    }
}

struct EarnedBadge: Identifiable, Equatable {
    let kind: BadgeKind
    let tier: Int

    var id: String { "\(kind.rawValue)-\(tier)" }

    var title: String {
        switch kind {
        case .dailyPercentile:
            return "Top \(tier)% Daily"
        case .loginStreak, .dailyStreak, .pvpWinStreak:
            return "\(kind.label) · \(tier)"
        case .pvpDailyWins:
            return "\(kind.label) · \(tier) today"
        case .flawlessDaily, .cleanSweep, .fullMenuDaily, .game7:
            return kind.label
        default:
            return "\(kind.label) · \(tier)"
        }
    }

    var tierColor: Color {
        BadgeTier.color(for: tier)
    }
}

enum BadgeTier {
    static func color(for tier: Int) -> Color {
        switch tier {
        case 100: return Color(red: 0.55, green: 0.75, blue: 1.0)   // diamond
        case 25: return Color(red: 0.62, green: 0.35, blue: 0.85)    // purple
        case 10: return Color(red: 0.95, green: 0.78, blue: 0.15)    // gold
        case 5: return Color(red: 0.72, green: 0.74, blue: 0.78)     // silver
        default: return Color(red: 0.78, green: 0.52, blue: 0.28)    // bronze
        }
    }

    static func highestTier(for count: Int, thresholds: [Int] = BadgeKind.countTiers) -> Int? {
        thresholds.filter { count >= $0 }.max()
    }
}

enum BadgeCatalog {
    /// All badges a player has earned, highest tier per kind.
    static func earned(from stats: BadgeStats, loginStreak: Int, dailyStreak: Int) -> [EarnedBadge] {
        var badges: [EarnedBadge] = []

        if let tier = BadgeTier.highestTier(for: stats.dailyMaxWordHits) {
            badges.append(EarnedBadge(kind: .dailyMaxWord, tier: tier))
        }
        if let tier = BadgeTier.highestTier(for: stats.pvpMaxWordHits) {
            badges.append(EarnedBadge(kind: .pvpMaxWord, tier: tier))
        }
        if let tier = BadgeTier.highestTier(for: stats.speedBonusCount) {
            badges.append(EarnedBadge(kind: .speedBonus, tier: tier))
        }
        if let tier = BadgeTier.highestTier(for: stats.pvpWins) {
            badges.append(EarnedBadge(kind: .pvpWins, tier: tier))
        }
        if let tier = BadgeTier.highestTier(for: stats.pvpDailyWinsBest, thresholds: BadgeKind.dailyWinTiers) {
            badges.append(EarnedBadge(kind: .pvpDailyWins, tier: tier))
        }
        if let tier = BadgeTier.highestTier(for: stats.pvpWinStreakBest, thresholds: BadgeKind.winStreakTiers) {
            badges.append(EarnedBadge(kind: .pvpWinStreak, tier: tier))
        }

        let streakBest = max(stats.loginStreakBest, loginStreak)
        if streakBest >= 3 {
            let tier = streakBest >= 10 ? 10 : (streakBest >= 7 ? 7 : 3)
            badges.append(EarnedBadge(kind: .loginStreak, tier: tier))
        }

        let dailyBest = max(stats.dailyStreakBest, dailyStreak)
        if dailyBest >= 3 {
            let tier = dailyBest >= 7 ? 7 : 3
            badges.append(EarnedBadge(kind: .dailyStreak, tier: tier))
        }

        if stats.dailyPercentileBest > 0 {
            badges.append(EarnedBadge(kind: .dailyPercentile, tier: stats.dailyPercentileBest))
        }
        if stats.flawlessDailyCount > 0 {
            badges.append(EarnedBadge(kind: .flawlessDaily, tier: 1))
        }
        if stats.cleanSweepCount > 0 {
            badges.append(EarnedBadge(kind: .cleanSweep, tier: 1))
        }
        if stats.fullMenuDailyCount > 0 {
            badges.append(EarnedBadge(kind: .fullMenuDaily, tier: 1))
        }
        if let tier = BadgeTier.highestTier(for: stats.game7Count) {
            badges.append(EarnedBadge(kind: .game7, tier: tier))
        }

        return badges
    }

    /// Top badges to orbit the avatar border in pre-game (max 6).
    static func featured(from stats: BadgeStats, loginStreak: Int, dailyStreak: Int, limit: Int = 6) -> [EarnedBadge] {
        earned(from: stats, loginStreak: loginStreak, dailyStreak: dailyStreak)
            .sorted {
                if $0.kind.rarity != $1.kind.rarity { return $0.kind.rarity > $1.kind.rarity }
                return $0.tier > $1.tier
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Percentile rank → badge tier (lower rank fraction = better).
    static func percentileTier(rank: Int, total: Int) -> Int? {
        guard total > 0 else { return nil }
        let fraction = Double(rank) / Double(total)
        if fraction <= 0.01 { return 1 }
        if fraction <= 0.05 { return 5 }
        if fraction <= 0.10 { return 10 }
        if fraction <= 0.25 { return 25 }
        return nil
    }

    /// Closest unearned badge the player can work toward right now.
    static func nextBadgeHint(todayWins: Int, winStreak: Int) -> BadgeProgress? {
        func next(in thresholds: [Int], current: Int, kind: BadgeKind) -> BadgeProgress? {
            guard let target = thresholds.first(where: { current < $0 }) else { return nil }
            return BadgeProgress(kind: kind, current: current, nextThreshold: target)
        }

        let candidates = [
            next(in: BadgeKind.dailyWinTiers, current: todayWins, kind: .pvpDailyWins),
            next(in: BadgeKind.winStreakTiers, current: winStreak, kind: .pvpWinStreak),
        ].compactMap { $0 }

        return candidates.min { $0.remaining < $1.remaining }
    }

    /// Every badge track with live progress for the stats screen.
    static func allTracks(
        stats: BadgeStats,
        loginStreak: Int,
        dailyStreak: Int,
        todayWins: Int,
        winStreak: Int
    ) -> [BadgeTrackItem] {
        let loginBest = max(stats.loginStreakBest, loginStreak)
        let dailyBest = max(stats.dailyStreakBest, dailyStreak)

        return [
            countTrack(.pvpWins, current: stats.pvpWins),
            countTrack(.pvpMaxWord, current: stats.pvpMaxWordHits),
            countTrack(.speedBonus, current: stats.speedBonusCount),
            countTrack(.dailyMaxWord, current: stats.dailyMaxWordHits),
            countTrack(.game7, current: stats.game7Count),
            streakTrack(.loginStreak, current: loginBest, thresholds: BadgeKind.loginStreakTiers),
            streakTrack(.dailyStreak, current: dailyBest, thresholds: BadgeKind.dailyStreakTiers),
            liveCountTrack(.pvpDailyWins, current: todayWins, best: stats.pvpDailyWinsBest,
                           thresholds: BadgeKind.dailyWinTiers),
            liveCountTrack(.pvpWinStreak, current: winStreak, best: stats.pvpWinStreakBest,
                           thresholds: BadgeKind.winStreakTiers),
            percentileTrack(stats: stats),
            oneOffTrack(.flawlessDaily, count: stats.flawlessDailyCount),
            oneOffTrack(.cleanSweep, count: stats.cleanSweepCount),
            oneOffTrack(.fullMenuDaily, count: stats.fullMenuDailyCount),
        ]
    }

    private static func countTrack(
        _ kind: BadgeKind,
        current: Int
    ) -> BadgeTrackItem {
        let earned = BadgeTier.highestTier(for: current)
        let next = BadgeKind.countTiers.first { current < $0 }
        return BadgeTrackItem(
            kind: kind,
            current: current,
            nextThreshold: next,
            earnedTier: earned,
            detail: kind.detail)
    }

    private static func streakTrack(
        _ kind: BadgeKind,
        current: Int,
        thresholds: [Int]
    ) -> BadgeTrackItem {
        let earned = BadgeTier.highestTier(for: current, thresholds: thresholds)
        let next = thresholds.first { current < $0 }
        return BadgeTrackItem(
            kind: kind,
            current: current,
            nextThreshold: next,
            earnedTier: earned,
            detail: kind.detail)
    }

    /// Uses live session value for progress; `best` is only for earned tier display fallback.
    private static func liveCountTrack(
        _ kind: BadgeKind,
        current: Int,
        best: Int,
        thresholds: [Int]
    ) -> BadgeTrackItem {
        let earned = BadgeTier.highestTier(for: max(current, best), thresholds: thresholds)
        let next = thresholds.first { current < $0 }
        return BadgeTrackItem(
            kind: kind,
            current: current,
            nextThreshold: next,
            earnedTier: earned,
            detail: kind.detail)
    }

    private static func percentileTrack(stats: BadgeStats) -> BadgeTrackItem {
        let best = stats.dailyPercentileBest
        let earned = best > 0 ? best : nil
        let next: Int? = {
            if best == 0 { return 25 }
            return BadgeKind.percentileTiers.first { $0 < best }
        }()
        return BadgeTrackItem(
            kind: .dailyPercentile,
            current: best,
            nextThreshold: next,
            earnedTier: earned,
            detail: BadgeKind.dailyPercentile.detail)
    }

    private static func oneOffTrack(_ kind: BadgeKind, count: Int) -> BadgeTrackItem {
        BadgeTrackItem(
            kind: kind,
            current: min(count, 1),
            nextThreshold: count >= 1 ? nil : 1,
            earnedTier: count >= 1 ? 1 : nil,
            detail: kind.detail)
    }

    /// Plausible badge stats for AI opponents based on skill tier.
    static func aiStats(tier: Int) -> BadgeStats {
        var stats = BadgeStats()
        stats.dailyMaxWordHits = tier * 3 + Int.random(in: 0...8)
        stats.pvpMaxWordHits = tier + Int.random(in: 0...12)
        stats.speedBonusCount = tier * 4 + Int.random(in: 0...15)
        stats.pvpWins = tier * 2 + Int.random(in: 0...20)
        stats.dailyPercentileBest = [0, 0, 25, 25, 10, 10, 5, 5, 1][min(tier, 8)]
        if tier >= 9 && Bool.random() { stats.flawlessDailyCount = 1 }
        if tier >= 8 && Bool.random() { stats.cleanSweepCount = 1 }
        if tier >= 7 && Bool.random() { stats.game7Count = Int.random(in: 1...3) }
        stats.loginStreakBest = min(10, tier + Int.random(in: 0...4))
        stats.dailyStreakBest = min(7, tier / 2 + Int.random(in: 0...3))
        stats.pvpDailyWinsBest = min(10, tier / 2 + Int.random(in: 0...3))
        stats.pvpWinStreakBest = min(25, tier + Int.random(in: 0...5))
        return stats
    }
}
