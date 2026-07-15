import Foundation

enum GameConstants {
    static let pvpRackSize = 8
    static let roundSeconds = 24
    static let pvpRoundsToWin = 4
    static let pvpMaxRounds = 7
    static let matchmakingTimeoutSeconds = 20
    static let reconnectGraceSeconds = 20
    static let maxConsecutiveTiedReplays = 3
    static let dailyRackCounts = [5, 6, 7, 8, 9, 10]
    static let dailyRoundsPerPuzzle = 4
    static let freeDailyPuzzlesPerDay = 3
    static let baseLivesPerDay = 5
    static let maxStreakBonusLives = 5
    static let revealSeconds: Double = 3.0
    static let transitionSeconds: Double = 2.0

    /// Big daily racks (8+ tiles) get extra time to find long words.
    static func dailySeconds(forRackSize size: Int) -> Int {
        size >= 8 ? 30 : roundSeconds
    }

    /// Encodes tie-replay rounds into the submission `round` column (e.g. round 3
    /// replay 1 → 301) so both clients stay in sync without schema changes.
    static func submissionRoundKey(displayRound: Int, tieReplay: Int) -> Int {
        displayRound * 100 + tieReplay
    }
}

/// A human-vs-human match backed by Supabase (shared seed + submissions).
struct OnlineMatchConfig: Equatable, Identifiable {
    var id: String { matchId }
    let matchId: String
    let seed: String
    let opponentUserId: String
    let opponentUsername: String
    let isChallenger: Bool

    static func pvpRack(seed: String, round: Int, tieReplay: Int) -> [Character] {
        var rng = SeededRandom(string: "\(seed)-round\(round)-tie\(tieReplay)")
        return WordDictionary.shared.makeRack(size: GameConstants.pvpRackSize, rng: &rng)
    }
}

/// A pending or resolved friend challenge stored in Supabase.
struct MatchChallengeInvite: Identifiable, Equatable {
    let id: String
    let challengerId: String
    let opponentId: String
    let challengerUsername: String
    let opponentUsername: String
    let status: String
    let seed: String
    let matchId: String?
}

struct PlayerSubmission: Equatable, Codable {
    var word: String?
    var breakdown: ScoreBreakdown?
    var submittedAt: TimeInterval?   // seconds into the round
    var isValid: Bool = false

    var score: Int { isValid ? (breakdown?.total ?? 0) : 0 }
}

enum RoundOutcome: Equatable, Codable {
    case playerWins
    case opponentWins
    case tie
}

struct RoundResult: Equatable, Codable {
    var rack: [String]               // stored as strings for Codable simplicity
    var player: PlayerSubmission
    var opponent: PlayerSubmission
    var outcome: RoundOutcome
    var wasTieReplay: Bool = false
}

enum MatchOutcome: Equatable, Codable {
    case playerWins
    case opponentWins
    case tie                          // 3 consecutive tied replays
}

struct MatchRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var opponentName: String
    var rounds: [RoundResult]
    var outcome: MatchOutcome
    var playerRoundWins: Int
    var opponentRoundWins: Int
}

struct DailyPuzzleResult: Codable, Identifiable {
    var id: String                    // "2026-07-03-7"
    var date: String                  // "2026-07-03"
    var rackSize: Int
    var roundScores: [Int]
    var words: [String?]
    var totalScore: Int
    var completedAt = Date()

    /// Highest-scoring valid word of the run (invalid words are annotated "✕").
    var bestWord: (word: String, score: Int)? {
        var best: (String, Int)?
        for (index, word) in words.enumerated() {
            guard let word, !word.hasSuffix("✕"), index < roundScores.count,
                  roundScores[index] > 0 else { continue }
            if best == nil || roundScores[index] > best!.1 {
                best = (word, roundScores[index])
            }
        }
        return best
    }
}

extension DailyPuzzleResult {
    /// Whether the player may reveal the optimal words for this puzzle.
    /// Premium unlocks immediately after completing; free players see them the
    /// next day (once the puzzle's UTC date has passed).
    func topWordsUnlocked(isPremium: Bool, today: String = DailySeed.todayString()) -> Bool {
        isPremium || date < today
    }

    func shareText(
        perfectScore: Int? = nil,
        standing: (rank: Int, total: Int)? = nil
    ) -> String {
        var lines = ["Worded \(rackSize)-Letter Daily — \(totalScore) pts"]
        for (index, score) in roundScores.enumerated() {
            let length = words[index]?.replacingOccurrences(of: " ✕", with: "").count ?? 0
            let blurred = length > 0 ? String(repeating: "▮", count: length) : "—"
            lines.append("Rack \(index + 1): \(blurred) \(score) pts")
        }
        if let perfectScore {
            lines.append("Best possible: \(perfectScore) pts")
        }
        if let standing {
            let percentile = max(1, 100 - Int((Double(standing.rank) / Double(standing.total)) * 100))
            lines.append("\(standing.rank)/\(standing.total) · \(percentile)th percentile")
        }
        lines.append("Play today's puzzle: worded.app")
        return lines.joined(separator: "\n")
    }
}

/// One row of a daily leaderboard fetched from Supabase.
struct DailyLeaderboardEntry: Identifiable {
    let id = UUID()
    let username: String
    let score: Int
    let bestWord: String?
    let bestWordScore: Int?
}

/// Identifies today's puzzle deterministically for every player.
enum DailySeed {
    /// The puzzle "day" resets at local midnight so the daily rolls over at
    /// 12:00 AM in the player's own time zone (e.g. Eastern), not UTC.
    static func todayString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    static func rack(day: String, rackSize: Int, round: Int) -> [Character] {
        var rng = SeededRandom(string: "worded-daily-\(day)-size\(rackSize)-round\(round)")
        return WordDictionary.shared.makeRack(size: rackSize, rng: &rng)
    }
}
