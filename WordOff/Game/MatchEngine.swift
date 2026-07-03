import Foundation
import SwiftUI

/// Drives a full PvP match: 7 rounds, first to 4 round wins.
/// The opponent is either a hidden AI or (future) a remote human via Supabase.
@MainActor
final class MatchEngine: ObservableObject {
    enum Phase: Equatable {
        case searching                 // matchmaking spinner
        case intro                     // "Round N" splash
        case flipping                  // tiles whoosh in and flip
        case go                        // "GO!" flash
        case playing                   // 20s typing window
        case reveal                    // both words shown, winner highlighted
        case transition                // tiles slide out / new tiles slide in
        case matchOver
    }

    // MARK: - Published state

    @Published var phase: Phase = .searching
    @Published var roundNumber = 1              // display round (ties replay same number)
    @Published var rack: [Character] = []
    @Published var typedWord = ""
    @Published var lockedWord: String?          // last submitted word
    @Published var lockedAt: TimeInterval?
    @Published var secondsLeft = GameConstants.roundSeconds
    @Published var playerRoundWins = 0
    @Published var opponentRoundWins = 0
    @Published var rounds: [RoundResult] = []
    @Published var lastRound: RoundResult?
    @Published var matchOutcome: MatchOutcome?
    @Published var opponentHasSubmitted = false
    @Published var playerSatOut = false          // backgrounded during round

    let opponent: AIOpponent
    let opponentName: String
    let isFriendGame: Bool

    private var roundStart: Date?
    private var timerTask: Task<Void, Never>?
    private var opponentPlan: (word: String?, submitAt: TimeInterval) = (nil, 99)
    private var consecutiveTies = 0
    private var bannedWords: Set<String> = []    // words used in immediately-prior tied round
    private var opponentBanned: Set<String> = []
    private var seed = SeededRandom(seed: UInt64.random(in: 0...UInt64.max))
    private let haptics = Haptics()

    var onMatchComplete: ((MatchRecord) -> Void)?

    init(opponentName: String? = nil, isFriendGame: Bool = false) {
        let ai = AIOpponent.random()
        self.opponent = ai
        self.opponentName = opponentName ?? ai.username
        self.isFriendGame = isFriendGame
    }

    // MARK: - Match flow

    func startMatch() {
        phase = .searching
        // Fake queue time so AI fallback is indistinguishable from a human match.
        let queueDelay = Double.random(in: 2.5...9.0)
        Task {
            try? await Task.sleep(for: .seconds(queueDelay))
            guard !Task.isCancelled else { return }
            beginRound()
        }
    }

    func beginRound() {
        typedWord = ""
        lockedWord = nil
        lockedAt = nil
        playerSatOut = false
        opponentHasSubmitted = false
        secondsLeft = GameConstants.roundSeconds
        rack = LetterBag.drawRack(size: GameConstants.pvpRackSize, rng: &seed)

        // Plan the AI's move up front, avoiding banned tie-replay words.
        var plan = opponent.play(rack: rack)
        if let word = plan.word, opponentBanned.contains(word) {
            let alternatives = WordDictionary.shared.buildableWords(from: rack)
                .filter { !opponentBanned.contains($0) }
            plan.word = alternatives.max {
                Scoring.score(word: $0, rackSize: rack.count, firstSubmit: false).total <
                Scoring.score(word: $1, rackSize: rack.count, firstSubmit: false).total
            }
        }
        opponentPlan = plan

        phase = .intro
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            phase = .flipping
            SoundPlayer.shared.play(.whoosh)
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
                if !opponentHasSubmitted && elapsed >= opponentPlan.submitAt && opponentPlan.word != nil {
                    opponentHasSubmitted = true
                }
                if elapsed >= Double(GameConstants.roundSeconds) {
                    endRound()
                    return
                }
            }
        }
    }

    /// Player taps Submit: locks the current word. They may edit and resubmit,
    /// which updates the lock time (and can forfeit the speed bonus).
    func submitWord() {
        guard phase == .playing, let start = roundStart else { return }
        let word = typedWord.trimmingCharacters(in: .whitespaces).uppercased()
        guard !word.isEmpty else { return }
        lockedWord = word
        lockedAt = Date().timeIntervalSince(start)
        haptics.impact()
    }

    /// App went to background mid-round: sit out this round (anti-cheat).
    func playerLeftApp() {
        guard phase == .playing else { return }
        playerSatOut = true
        lockedWord = nil
        lockedAt = nil
        typedWord = ""
    }

    private func endRound() {
        timerTask?.cancel()

        // Auto-submit whatever is typed if never explicitly locked (no speed bonus applies anyway at deadline).
        var playerWord = lockedWord
        var playerTime = lockedAt
        if playerWord == nil, !playerSatOut {
            let typed = typedWord.trimmingCharacters(in: .whitespaces).uppercased()
            if !typed.isEmpty {
                playerWord = typed
                playerTime = Double(GameConstants.roundSeconds)
            }
        }

        var player = PlayerSubmission(word: playerWord, submittedAt: playerTime)
        var opp = PlayerSubmission(word: opponentPlan.word, submittedAt: opponentPlan.word == nil ? nil : opponentPlan.submitAt)

        // Tie-replay rule: banned words score 0.
        if let word = player.word, bannedWords.contains(word) { player.word = nil }

        player.isValid = player.word.map { WordDictionary.shared.validate(word: $0, rack: rack) } ?? false
        opp.isValid = opp.word.map { WordDictionary.shared.validate(word: $0, rack: rack) } ?? false

        let playerFirst = firstSubmitter(player: player, opponent: opp) == .player
        let oppFirst = firstSubmitter(player: player, opponent: opp) == .opponent

        if player.isValid, let word = player.word {
            player.breakdown = Scoring.score(word: word, rackSize: rack.count, firstSubmit: playerFirst)
        }
        if opp.isValid, let word = opp.word {
            opp.breakdown = Scoring.score(word: word, rackSize: rack.count, firstSubmit: oppFirst)
        }

        let outcome: RoundOutcome
        if player.score > opp.score { outcome = .playerWins }
        else if opp.score > player.score { outcome = .opponentWins }
        else { outcome = .tie }

        let result = RoundResult(
            rack: rack.map(String.init), player: player, opponent: opp,
            outcome: outcome, wasTieReplay: consecutiveTies > 0)
        rounds.append(result)
        lastRound = result

        switch outcome {
        case .playerWins:
            playerRoundWins += 1
            consecutiveTies = 0
            bannedWords = []
            opponentBanned = []
            SoundPlayer.shared.play(.win)
        case .opponentWins:
            opponentRoundWins += 1
            consecutiveTies = 0
            bannedWords = []
            opponentBanned = []
            SoundPlayer.shared.play(.lose)
        case .tie:
            consecutiveTies += 1
            if let word = player.word { bannedWords.insert(word) }
            if let word = opp.word { opponentBanned.insert(word) }
        }

        phase = .reveal
        Task {
            try? await Task.sleep(for: .seconds(GameConstants.revealSeconds))
            advanceAfterReveal(outcome: outcome)
        }
    }

    private enum Submitter { case player, opponent, neither }

    private func firstSubmitter(player: PlayerSubmission, opponent: PlayerSubmission) -> Submitter {
        // Speed bonus requires a valid, explicitly-submitted word before the deadline.
        let deadline = Double(GameConstants.roundSeconds)
        let playerTime = (player.word != nil && (player.submittedAt ?? deadline) < deadline) ? player.submittedAt : nil
        let oppTime = opponent.word != nil ? opponent.submittedAt : nil
        switch (playerTime, oppTime) {
        case (nil, nil): return .neither
        case (.some, nil): return .player
        case (nil, .some): return .opponent
        case (.some(let p), .some(let o)): return p <= o ? .player : .opponent
        }
    }

    private func advanceAfterReveal(outcome: RoundOutcome) {
        if playerRoundWins >= GameConstants.pvpRoundsToWin {
            finishMatch(.playerWins)
            return
        }
        if opponentRoundWins >= GameConstants.pvpRoundsToWin {
            finishMatch(.opponentWins)
            return
        }
        if outcome == .tie && consecutiveTies >= GameConstants.maxConsecutiveTiedReplays {
            finishMatch(.tie)
            return
        }
        if outcome != .tie {
            roundNumber += 1
        }
        phase = .transition
        Task {
            try? await Task.sleep(for: .seconds(GameConstants.transitionSeconds))
            beginRound()
        }
    }

    private func finishMatch(_ outcome: MatchOutcome) {
        matchOutcome = outcome
        phase = .matchOver
        let record = MatchRecord(
            opponentName: opponentName,
            rounds: rounds,
            outcome: outcome,
            playerRoundWins: playerRoundWins,
            opponentRoundWins: opponentRoundWins)
        onMatchComplete?(record)
        SoundPlayer.shared.play(outcome == .playerWins ? .fanfare : .lose)
    }

    /// Resets all state and starts a fresh match against the same opponent.
    func rematch() {
        timerTask?.cancel()
        roundNumber = 1
        playerRoundWins = 0
        opponentRoundWins = 0
        rounds = []
        lastRound = nil
        matchOutcome = nil
        consecutiveTies = 0
        bannedWords = []
        opponentBanned = []
        phase = .searching
        // AI "accepts" after a believable delay.
        Task {
            try? await Task.sleep(for: .seconds(Double.random(in: 1.0...3.0)))
            beginRound()
        }
    }

    func cancel() {
        timerTask?.cancel()
    }
}
