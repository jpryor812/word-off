import Foundation

enum GameConstants {
    static let pvpRackSize = 8
    static let roundSeconds = 24
    static let pvpRoundsToWin = 4
    static let pvpMaxRounds = 7
    /// Legacy search-window constant (timeout chooser removed — human search
    /// continues until match or Cancel). Kept for any remaining schedule helpers.
    // static let matchmakingTimeoutSeconds = 20
    // static let matchmakingTimeoutSeconds = 60
    static let matchmakingTimeoutSeconds = 60
    static let reconnectGraceSeconds = 20
    static let maxConsecutiveTiedReplays = 3
    static let dailyRackCounts = [5, 6, 7, 8, 9, 10]
    static let dailyRoundsPerPuzzle = 4
    /// Sentinel `rack_size` for The Ladder daily (5→6→7→8→9→10 in one run).
    static let ladderDailySentinel = 0
    static let ladderRoundSizes = [5, 6, 7, 8, 9, 10]
    static let freeDailyPuzzlesPerDay = 3

    static func isLadderDaily(_ rackSize: Int) -> Bool {
        rackSize == ladderDailySentinel
    }

    static func dailyDisplayTitle(rackSize: Int) -> String {
        isLadderDaily(rackSize) ? "The Ladder" : "\(rackSize)-Letter Daily"
    }

    static func dailyRounds(forRackSize rackSize: Int) -> Int {
        isLadderDaily(rackSize) ? ladderRoundSizes.count : dailyRoundsPerPuzzle
    }

    static func dailyRoundRackSize(puzzleRackSize: Int, roundIndex: Int) -> Int {
        if isLadderDaily(puzzleRackSize) {
            return ladderRoundSizes[min(max(roundIndex, 0), ladderRoundSizes.count - 1)]
        }
        return puzzleRackSize
    }
    static let baseLivesPerDay = 5
    static let maxStreakBonusLives = 5
    static let revealSeconds: Double = 3.0
    /// Friend challenge invites expire if not accepted within this window.
    static let challengeInviteTTL: TimeInterval = 6 * 60 * 60
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
    var createdAt: Date? = nil
    var updatedAt: Date? = nil

    var isExpired: Bool {
        if status == "expired" { return true }
        guard status == "pending", let createdAt else { return false }
        return Date().timeIntervalSince(createdAt) >= GameConstants.challengeInviteTTL
    }

    /// Accepted recently enough that auto-starting the match still makes sense.
    var isFreshlyAccepted: Bool {
        guard status == "accepted" else { return false }
        let stamp = updatedAt ?? createdAt
        guard let stamp else { return false }
        return Date().timeIntervalSince(stamp) <= 5 * 60
    }
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
    /// Scoring round (1…7). Tie replays keep the same number.
    var displayRound: Int = 1
    /// 1 = first play (R3), 2 = first tie replay (R3.2), etc.
    var attempt: Int = 1

    /// e.g. "R3" or "R3.2"
    var label: String {
        attempt <= 1 ? "R\(displayRound)" : "R\(displayRound).\(attempt)"
    }
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

    var displayTitle: String { GameConstants.dailyDisplayTitle(rackSize: rackSize) }

    var isLadder: Bool { GameConstants.isLadderDaily(rackSize) }

    func shareText(
        perfectScore: Int? = nil,
        standing: (rank: Int, total: Int)? = nil
    ) -> String {
        var lines = ["Worded \(displayTitle) — \(totalScore) pts"]
        for (index, score) in roundScores.enumerated() {
            let length = words[index]?.replacingOccurrences(of: " ✕", with: "").count ?? 0
            let blurred = length > 0 ? String(repeating: "▮", count: length) : "—"
            let sizeLabel = GameConstants.dailyRoundRackSize(puzzleRackSize: rackSize, roundIndex: index)
            lines.append("Rack \(index + 1) (\(sizeLabel)): \(blurred) \(score) pts")
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
    var userId: String? = nil
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
        if GameConstants.isLadderDaily(rackSize) {
            return ladderRack(day: day, round: round)
        }
        var rng = SeededRandom(string: "worded-daily-\(day)-size\(rackSize)-round\(round)")
        return WordDictionary.shared.makeRack(size: rackSize, rng: &rng)
    }

    /// Onboarding practice rack: WORDSS jumbled (W=4, D=2, S=1) so point values are obvious.
    static func practiceRack(day: String, rackSize: Int) -> [Character] {
        // Fixed scramble of W-O-R-D-S-S — ignores day/size so the teachable letters stay put.
        _ = day
        _ = rackSize
        return Array("RSWDOS")
    }

    /// Letters whose point badges are highlighted during the practice teach step.
    static let practiceHighlightLetters: Set<Character> = ["W", "D", "S"]

    /// Ladder uses its own seed stream so it doesn't collide with fixed-size dailies.
    static func ladderRack(day: String, round: Int) -> [Character] {
        let size = GameConstants.dailyRoundRackSize(
            puzzleRackSize: GameConstants.ladderDailySentinel,
            roundIndex: round)
        var rng = SeededRandom(string: "worded-daily-\(day)-ladder-round\(round)")
        return WordDictionary.shared.makeRack(size: size, rng: &rng)
    }
}
