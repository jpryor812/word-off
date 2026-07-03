import Foundation
import SwiftUI

/// Drives one daily puzzle: 4 seeded racks of a given size, 20s each,
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

    let day: String
    let rackSize: Int

    private var roundStart: Date?
    private var timerTask: Task<Void, Never>?
    private let haptics = Haptics()

    var totalScore: Int { roundScores.reduce(0, +) }

    init(day: String = DailySeed.todayString(), rackSize: Int) {
        self.day = day
        self.rackSize = rackSize
    }

    func start() {
        beginRack()
    }

    private func beginRack() {
        typedWord = ""
        lockedWord = nil
        satOut = false
        lastBreakdown = nil
        secondsLeft = GameConstants.roundSeconds
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
                let remaining = max(0, GameConstants.roundSeconds - Int(elapsed))
                if remaining != secondsLeft {
                    secondsLeft = remaining
                    if remaining <= 5 && remaining > 0 { SoundPlayer.shared.play(.tick) }
                }
                if elapsed >= Double(GameConstants.roundSeconds) {
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
        lockedWord = word
        haptics.impact()
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
