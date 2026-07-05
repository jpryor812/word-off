import Foundation
import SwiftUI

/// Drives one daily puzzle: 4 seeded racks of a given size, timed rounds,
/// cumulative score. Backgrounding forfeits the current rack (anti-cheat).
@MainActor
final class DailyEngine: ObservableObject {
    enum Phase: Equatable {
        case intro
        case flipping
        case go
        case playing
        case rackDone          // brief score interstitial between racks
        case finished
    }

    @Published var phase: Phase = .intro
    @Published var rackIndex = 0
    @Published var rack: [Character] = []
    @Published var typedWord = ""
    @Published var lockedWord: String?
    @Published var secondsLeft = GameConstants.roundSeconds
    @Published var roundScores: [Int] = []
    @Published var words: [String?] = []
    @Published var lastBreakdown: ScoreBreakdown?
    @Published var satOut = false
    @Published var submissionFeedback: String?

    let day: String
    let rackSize: Int
    let roundDuration: Int

    private var roundStart: Date?
    private var timerTask: Task<Void, Never>?
    private let haptics = Haptics()

    var totalScore: Int { roundScores.reduce(0, +) }

    init(day: String = DailySeed.todayString(), rackSize: Int) {
        self.day = day
        self.rackSize = rackSize
        self.roundDuration = GameConstants.dailySeconds(forRackSize: rackSize)
        self.secondsLeft = roundDuration
    }

    func start() {
        beginRack()
    }

    private func beginRack() {
        typedWord = ""
        lockedWord = nil
        satOut = false
        lastBreakdown = nil
        submissionFeedback = nil
        secondsLeft = roundDuration
        rack = DailySeed.rack(day: day, rackSize: rackSize, round: rackIndex)
        phase = .flipping
        SoundPlayer.shared.play(.whoosh)
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            SoundPlayer.shared.play(.flip)
            phase = .go
            haptics.impact()
            try? await Task.sleep(for: .seconds(0.7))
            startPlaying()
        }
    }

    private func startPlaying() {
        phase = .playing
        roundStart = Date()
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.1))
                guard phase == .playing, let start = roundStart else { return }
                let elapsed = Date().timeIntervalSince(start)
                let remaining = max(0, roundDuration - Int(elapsed))
                if remaining != secondsLeft {
                    secondsLeft = remaining
                    if remaining <= 5 && remaining > 0 { SoundPlayer.shared.play(.tick) }
                }
                if elapsed >= Double(roundDuration) {
                    endRack()
                    return
                }
            }
        }
    }

    func submitWord() {
        guard phase == .playing else { return }
        let word = typedWord.trimmingCharacters(in: .whitespaces).uppercased()
        guard !word.isEmpty else { return }
        guard Scoring.isBuildable(word: word, from: rack) else {
            submissionFeedback = "You can only use the letters on the rack!"
            SoundPlayer.shared.play(.error)
            return
        }
        guard WordDictionary.shared.contains(word) else {
            submissionFeedback = "\(word) isn't a word — keep trying!"
            SoundPlayer.shared.play(.error)
            return
        }
        submissionFeedback = nil
        lockedWord = word
        haptics.impact()
    }

    /// Rearranges the rack tiles to help the player spot words. Purely cosmetic
    /// (order never affects validity), and only allowed during active play.
    func shuffleRack() {
        guard phase == .playing, rack.count > 1 else { return }
        let previous = rack
        repeat {
            for i in stride(from: rack.count - 1, to: 0, by: -1) {
                rack.swapAt(i, Int.random(in: 0...i))
            }
        } while rack == previous
        SoundPlayer.shared.play(.whoosh)
        haptics.impact()
    }

    /// Ends the current rack immediately once the player has locked a word in,
    /// so they don't have to wait out the clock when they're happy with it.
    func finishRoundEarly() {
        guard phase == .playing, lockedWord != nil else { return }
        endRack()
    }

    func playerLeftApp() {
        guard phase == .playing else { return }
        satOut = true
        lockedWord = nil
        typedWord = ""
    }

    private func endRack() {
        timerTask?.cancel()
        var word = lockedWord
        if word == nil, !satOut {
            let typed = typedWord.trimmingCharacters(in: .whitespaces).uppercased()
            if !typed.isEmpty { word = typed }
        }

        var score = 0
        if let word, WordDictionary.shared.validate(word: word, rack: rack) {
            let breakdown = Scoring.score(word: word, rackSize: rack.count, firstSubmit: false)
            score = breakdown.total
            lastBreakdown = breakdown
        } else {
            word = word.map { $0 + " ✕" } // annotate invalid for the interstitial
        }
        roundScores.append(score)
        words.append(word)
        SoundPlayer.shared.play(score > 0 ? .win : .lose)

        if rackIndex + 1 >= GameConstants.dailyRoundsPerPuzzle {
            phase = .finished
        } else {
            phase = .rackDone
            Task {
                try? await Task.sleep(for: .seconds(2.2))
                rackIndex += 1
                beginRack()
            }
        }
    }

    func makeResult() -> DailyPuzzleResult {
        DailyPuzzleResult(
            id: "\(day)-\(rackSize)",
            date: day,
            rackSize: rackSize,
            roundScores: roundScores,
            words: words,
            totalScore: totalScore)
    }

    func cancel() {
        timerTask?.cancel()
    }
}

/// Recomputes the optimal plays for a daily puzzle. Because every rack is
/// seeded deterministically by day/size/round, this reproduces the exact tiles
/// each player saw and finds the highest-scoring word(s) for every rack.
enum DailySolver {
    struct RackSolution: Identifiable, Sendable {
        let id: Int              // round index (0-based)
        let rack: [Character]
        let maxScore: Int
        let words: [String]      // all words tied for maxScore, sorted A–Z
    }

    /// Speed bonus is PvP-only; daily "best possible" is letter values alone.
    static func solve(day: String, rackSize: Int) -> [RackSolution] {
        (0..<GameConstants.dailyRoundsPerPuzzle).map { round in
            let rack = DailySeed.rack(day: day, rackSize: rackSize, round: round)
            var best = 0
            var words: [String] = []
            // Prefer recognizable common words; fall back to the full dictionary
            // only if a rack happens to have no common plays.
            var pool = WordDictionary.shared.buildableCommonWords(from: rack)
            if pool.isEmpty { pool = WordDictionary.shared.buildableWords(from: rack) }
            for word in pool {
                let score = Scoring.score(word: word, rackSize: rack.count, firstSubmit: false).total
                if score > best {
                    best = score
                    words = [word]
                } else if score == best {
                    words.append(word)
                }
            }
            return RackSolution(id: round, rack: rack, maxScore: best, words: words.sorted())
        }
    }

    /// Sum of the best common-word score on each rack — the "perfect" daily total.
    static func perfectScore(day: String, rackSize: Int) -> Int {
        solve(day: day, rackSize: rackSize).reduce(0) { $0 + $1.maxScore }
    }

    /// Highest-scoring word(s) buildable from an arbitrary rack (used by the
    /// PvP match "top words" reveal). Prefers recognizable common words.
    static func bestWords(from rack: [Character], limit: Int = 6) -> (score: Int, words: [String]) {
        var pool = WordDictionary.shared.buildableCommonWords(from: rack)
        if pool.isEmpty { pool = WordDictionary.shared.buildableWords(from: rack) }
        var best = 0
        var words: [String] = []
        for word in pool {
            let score = Scoring.score(word: word, rackSize: rack.count, firstSubmit: false).total
            if score > best {
                best = score
                words = [word]
            } else if score == best {
                words.append(word)
            }
        }
        return (best, Array(words.sorted().prefix(limit)))
    }
}
