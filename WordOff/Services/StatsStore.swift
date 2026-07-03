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
        var matches: [MatchRecord] = []

        var averageWordScore: Double {
            totalWordsPlayed == 0 ? 0 : Double(totalWordScore) / Double(totalWordsPlayed)
        }
    }

    @Published private(set) var stats = Stats()

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
        switch match.outcome {
        case .playerWins: stats.wins += 1
        case .opponentWins: stats.losses += 1
        case .tie: stats.ties += 1
        }
        for round in match.rounds where round.player.isValid {
            stats.totalWordScore += round.player.score
            stats.totalWordsPlayed += 1
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
}
