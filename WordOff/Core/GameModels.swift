import Foundation

enum GameConstants {
    static let pvpRackSize = 9
    static let roundSeconds = 20
    static let pvpRoundsToWin = 4
    static let pvpMaxRounds = 7
    static let matchmakingTimeoutSeconds = 15
    static let reconnectGraceSeconds = 20
    static let maxConsecutiveTiedReplays = 3
    static let dailyRackCounts = [5, 6, 7, 8, 9]
    static let dailyRoundsPerPuzzle = 4
    static let freeDailyPuzzlesPerDay = 3
    static let baseLivesPerDay = 5
    static let maxStreakBonusLives = 5
    static let revealSeconds: Double = 3.0
    static let transitionSeconds: Double = 2.0
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
}

/// Identifies today's puzzle deterministically for every player.
enum DailySeed {
    static func todayString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func rack(day: String, rackSize: Int, round: Int) -> [Character] {
        var rng = SeededRandom(string: "wordoff-daily-\(day)-size\(rackSize)-round\(round)")
        return LetterBag.drawRack(size: rackSize, rng: &rng)
    }
}
