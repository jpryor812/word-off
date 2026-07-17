import Foundation

/// Tracks badge progress locally and syncs to Supabase when online.
@MainActor
final class BadgeStore: ObservableObject {
    @Published private(set) var stats = BadgeStats()

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("badge_stats.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(BadgeStats.self, from: data) {
            stats = decoded
        }
    }

    var featuredBadges: [EarnedBadge] {
        BadgeCatalog.featured(from: stats, loginStreak: 0, dailyStreak: 0)
    }

    func featuredBadges(loginStreak: Int, dailyStreak: Int) -> [EarnedBadge] {
        BadgeCatalog.featured(from: stats, loginStreak: loginStreak, dailyStreak: dailyStreak)
    }

    func currentTracks(
        loginStreak: Int,
        dailyStreak: Int,
        todayWins: Int,
        winStreak: Int
    ) -> [BadgeTrackItem] {
        BadgeCatalog.allTracks(
            stats: stats,
            loginStreak: loginStreak,
            dailyStreak: dailyStreak,
            todayWins: todayWins,
            winStreak: winStreak)
    }

    // MARK: - Recording events

    func recordDailyCompletion(
        day: String,
        rackSize: Int,
        words: [String?],
        roundScores: [Int],
        rank: Int?,
        total: Int?,
        completedSizesToday: Int
    ) {
        let solutions = DailySolver.solve(day: day, rackSize: rackSize)
        var maxHits = 0
        for (index, solution) in solutions.enumerated() {
            guard index < words.count, index < roundScores.count,
                  let word = words[index], !word.hasSuffix("✕"),
                  roundScores[index] > 0 else { continue }
            let playerScore = Scoring.score(
                word: word, rackSize: solution.rack.count, firstSubmit: false).total
            if playerScore >= solution.maxScore && solution.maxScore > 0 {
                maxHits += 1
            }
        }
        if maxHits > 0 {
            stats.dailyMaxWordHits += maxHits
        }
        if maxHits == solutions.count && !solutions.isEmpty {
            stats.flawlessDailyCount += 1
        }
        // Full Menu = all fixed-size dailies (5–10). The Ladder does not count.
        if completedSizesToday >= GameConstants.dailyRackCounts.count {
            stats.fullMenuDailyCount += 1
        }
        if let rank, let total, let tier = BadgeCatalog.percentileTier(rank: rank, total: total) {
            if stats.dailyPercentileBest == 0 || tier < stats.dailyPercentileBest {
                stats.dailyPercentileBest = tier
            }
        }
        persistAndSync()
    }

    func recordPvPRound(rack: [Character], playerWord: String?, playerBreakdown: ScoreBreakdown?) {
        guard let word = playerWord,
              WordDictionary.shared.validate(word: word, rack: rack) else { return }

        let maxScore = DailySolver.bestWords(from: rack).score
        let letterScore = playerBreakdown?.letterPoints
            ?? Scoring.score(word: word, rackSize: rack.count, firstSubmit: false).letterPoints
        if maxScore > 0 && letterScore >= maxScore {
            stats.pvpMaxWordHits += 1
        }
        if (playerBreakdown?.speedBonus ?? 0) > 0 {
            stats.speedBonusCount += 1
        }
        persistAndSync()
    }

    func recordMatchComplete(
        outcome: MatchOutcome,
        playerRoundWins: Int,
        opponentRoundWins: Int,
        totalRounds: Int,
        todayWins: Int,
        winStreak: Int
    ) {
        if outcome == .playerWins {
            stats.pvpWins += 1
        }
        if todayWins > stats.pvpDailyWinsBest {
            stats.pvpDailyWinsBest = todayWins
        }
        if winStreak > stats.pvpWinStreakBest {
            stats.pvpWinStreakBest = winStreak
        }
        if outcome == .playerWins && playerRoundWins == totalRounds && totalRounds > 0 {
            stats.cleanSweepCount += 1
        }
        // Full 7-round thriller: first to 4, opponent took 3 (4–3).
        if outcome == .playerWins && playerRoundWins == 4 && opponentRoundWins == 3 {
            stats.game7Count += 1
        }
        persistAndSync()
    }

    func refreshStreakBadges(loginStreak: Int, dailyStreak: Int) {
        var changed = false
        if loginStreak > stats.loginStreakBest {
            stats.loginStreakBest = loginStreak
            changed = true
        }
        if dailyStreak > stats.dailyStreakBest {
            stats.dailyStreakBest = dailyStreak
            changed = true
        }
        if changed { persistAndSync() }
    }

    func applyRemoteStats(_ remote: BadgeStats) {
        stats = merge(local: stats, remote: remote)
        persistLocal()
    }

    // MARK: - Supabase

    func syncFromServer() async {
        guard SupabaseConfig.isConfigured,
              let session = SupabaseClient.shared.currentSession else { return }
        do {
            let data = try await SupabaseClient.shared.request(
                table: "profiles",
                query: "id=eq.\(session.userId)&select=badge_stats")
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = rows.first,
                  let badgeJSON = row["badge_stats"],
                  JSONSerialization.isValidJSONObject(badgeJSON),
                  let badgeData = try? JSONSerialization.data(withJSONObject: badgeJSON),
                  let remote = try? JSONDecoder().decode(BadgeStats.self, from: badgeData) else {
                return
            }
            stats = merge(local: stats, remote: remote)
            persistLocal()
        } catch {
            // Offline — local stats are the source of truth until next sync.
        }
    }

    func fetchStats(forUsername username: String) async -> BadgeStats? {
        guard SupabaseConfig.isConfigured else { return nil }
        do {
            let data = try await SupabaseClient.shared.request(
                table: "profiles",
                query: "username=eq.\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username)&select=badge_stats")
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = rows.first,
                  let badgeJSON = row["badge_stats"],
                  JSONSerialization.isValidJSONObject(badgeJSON),
                  let badgeData = try? JSONSerialization.data(withJSONObject: badgeJSON),
                  let remote = try? JSONDecoder().decode(BadgeStats.self, from: badgeData) else {
                return nil
            }
            return remote
        } catch {
            return nil
        }
    }

    func clearAll() {
        stats = BadgeStats()
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Persistence

    private func persistAndSync() {
        persistLocal()
        Task { await syncToServer() }
    }

    private func persistLocal() {
        if let data = try? JSONEncoder().encode(stats) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func syncToServer() async {
        guard SupabaseConfig.isConfigured,
              let session = SupabaseClient.shared.currentSession else { return }
        guard let statsData = try? JSONEncoder().encode(stats),
              let statsObject = try? JSONSerialization.jsonObject(with: statsData) else { return }
        let payload: [String: Any] = ["badge_stats": statsObject]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        _ = try? await SupabaseClient.shared.request(
            table: "profiles",
            method: "PATCH",
            query: "id=eq.\(session.userId)",
            body: body)
    }

    /// Keep the higher count for each stat when merging local + remote.
    private func merge(local: BadgeStats, remote: BadgeStats) -> BadgeStats {
        var merged = local
        merged.dailyMaxWordHits = max(local.dailyMaxWordHits, remote.dailyMaxWordHits)
        merged.pvpMaxWordHits = max(local.pvpMaxWordHits, remote.pvpMaxWordHits)
        merged.speedBonusCount = max(local.speedBonusCount, remote.speedBonusCount)
        merged.pvpWins = max(local.pvpWins, remote.pvpWins)
        merged.flawlessDailyCount = max(local.flawlessDailyCount, remote.flawlessDailyCount)
        merged.cleanSweepCount = max(local.cleanSweepCount, remote.cleanSweepCount)
        merged.fullMenuDailyCount = max(local.fullMenuDailyCount, remote.fullMenuDailyCount)
        merged.loginStreakBest = max(local.loginStreakBest, remote.loginStreakBest)
        merged.dailyStreakBest = max(local.dailyStreakBest, remote.dailyStreakBest)
        merged.pvpDailyWinsBest = max(local.pvpDailyWinsBest, remote.pvpDailyWinsBest)
        merged.pvpWinStreakBest = max(local.pvpWinStreakBest, remote.pvpWinStreakBest)
        merged.game7Count = max(local.game7Count, remote.game7Count)
        if remote.dailyPercentileBest > 0 {
            if merged.dailyPercentileBest == 0 || remote.dailyPercentileBest < merged.dailyPercentileBest {
                merged.dailyPercentileBest = remote.dailyPercentileBest
            }
        }
        return merged
    }
}
