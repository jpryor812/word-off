import Foundation

/// Local win/loss record and word stats. Mirrors to Supabase when configured.
@MainActor
final class StatsStore: ObservableObject {
    struct Stats: Codable {
        var wins = 0
        var losses = 0
        var ties = 0        // tracked for display; ties don't affect W/L record
        var totalWordScore = 0
        var totalWordsPlayed = 0
        // Speed tracking (PvP only, where a submit time exists): cumulative
        // points earned per second spent, surfaced on the home screen.
        var pvpWordScore = 0
        var pvpSubmitSeconds: Double = 0
        var matches: [MatchRecord] = []
        // Today's PvP record (local calendar day) and active win streak.
        var pvpDay = ""
        var pvpDayWins = 0
        var pvpDayLosses = 0
        var pvpWinStreak = 0

        var averageWordScore: Double {
            totalWordsPlayed == 0 ? 0 : Double(totalWordScore) / Double(totalWordsPlayed)
        }

        var pointsPerSecond: Double {
            pvpSubmitSeconds <= 0 ? 0 : Double(pvpWordScore) / pvpSubmitSeconds
        }

        init() {}

        // Resilient decode: older saves lack the newer keys, so default them
        // instead of throwing (which would wipe a player's record on upgrade).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            wins = try c.decodeIfPresent(Int.self, forKey: .wins) ?? 0
            losses = try c.decodeIfPresent(Int.self, forKey: .losses) ?? 0
            ties = try c.decodeIfPresent(Int.self, forKey: .ties) ?? 0
            totalWordScore = try c.decodeIfPresent(Int.self, forKey: .totalWordScore) ?? 0
            totalWordsPlayed = try c.decodeIfPresent(Int.self, forKey: .totalWordsPlayed) ?? 0
            pvpWordScore = try c.decodeIfPresent(Int.self, forKey: .pvpWordScore) ?? 0
            pvpSubmitSeconds = try c.decodeIfPresent(Double.self, forKey: .pvpSubmitSeconds) ?? 0
            matches = try c.decodeIfPresent([MatchRecord].self, forKey: .matches) ?? []
            pvpDay = try c.decodeIfPresent(String.self, forKey: .pvpDay) ?? ""
            pvpDayWins = try c.decodeIfPresent(Int.self, forKey: .pvpDayWins) ?? 0
            pvpDayLosses = try c.decodeIfPresent(Int.self, forKey: .pvpDayLosses) ?? 0
            pvpWinStreak = try c.decodeIfPresent(Int.self, forKey: .pvpWinStreak) ?? 0
        }
    }

    @Published private(set) var stats = Stats()

    var todayRecord: (wins: Int, losses: Int) {
        rollDayIfNeeded()
        return (stats.pvpDayWins, stats.pvpDayLosses)
    }

    var winStreak: Int {
        rollDayIfNeeded()
        return stats.pvpWinStreak
    }

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("stats.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Stats.self, from: data) {
            stats = decoded
        }
    }

    func record(match: MatchRecord) {
        rollDayIfNeeded()
        switch match.outcome {
        case .playerWins:
            stats.wins += 1
            stats.pvpDayWins += 1
            stats.pvpWinStreak += 1
        case .opponentWins:
            stats.losses += 1
            stats.pvpDayLosses += 1
            stats.pvpWinStreak = 0
        case .tie:
            stats.ties += 1
        }
        for round in match.rounds where round.player.isValid {
            stats.totalWordScore += round.player.score
            stats.totalWordsPlayed += 1
            if let seconds = round.player.submittedAt, seconds > 0 {
                stats.pvpWordScore += round.player.score
                stats.pvpSubmitSeconds += seconds
            }
        }
        stats.matches.insert(match, at: 0)
        if stats.matches.count > 50 { stats.matches.removeLast() }
        persist()
    }

    func recordDailyWords(scores: [Int]) {
        for score in scores where score > 0 {
            stats.totalWordScore += score
            stats.totalWordsPlayed += 1
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(stats) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func rollDayIfNeeded() {
        let today = Self.localDayString()
        if stats.pvpDay != today {
            stats.pvpDay = today
            stats.pvpDayWins = 0
            stats.pvpDayLosses = 0
        }
    }

    private static func localDayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
