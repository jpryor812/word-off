import Foundation
import SwiftUI

/// Drives a full PvP match: 7 rounds, first to 4 round wins.
/// The opponent is either a hidden AI or (future) a remote human via Supabase.
@MainActor
final class MatchEngine: ObservableObject {
    enum Phase: Equatable {
        case searching                 // matchmaking spinner
        case matchupIntro            // VS avatars + badges (once per match)
        case intro                     // "Round N" splash (round 2+)
        case flipping                  // tiles whoosh in and flip
        case go                        // "GO!" flash
        case playing                   // timed typing window
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
    @Published var submissionFeedback: String?   // "XYZ isn't a word!" etc.
    @Published var opponentBadgeStats: BadgeStats

    let opponent: AIOpponent
    let opponentName: String
    let isFriendGame: Bool
    let aiAfterMatchmakingTimeout: Bool
    let onlineConfig: OnlineMatchConfig?
    weak var challengeService: MatchChallengeService?

    var isOnlineMatch: Bool { onlineConfig != nil }

    private var roundStart: Date?
    private var timerTask: Task<Void, Never>?
    private var opponentPlan: (word: String?, submitAt: TimeInterval) = (nil, 99)
    private var consecutiveTies = 0
    private var roundEnding = false              // guards early-end scheduling
    private var seed = SeededRandom(seed: UInt64.random(in: 0...UInt64.max))
    private let haptics = Haptics.shared
    /// Remaining full-rack (8-letter) plays budgeted for this AI match.
    private var aiBingosRemaining: Int = 0

    var onMatchComplete: ((MatchRecord) -> Void)?
    var onRoundScored: ((RoundResult) -> Void)?

    /// e.g. "3" or "3.2" for the in-game header / intro.
    var roundDisplayLabel: String {
        consecutiveTies == 0 ? "\(roundNumber)" : "\(roundNumber).\(consecutiveTies + 1)"
    }

    init(
        onlineMatch: OnlineMatchConfig? = nil,
        opponentName: String? = nil,
        isFriendGame: Bool = false,
        aiAfterMatchmakingTimeout: Bool = false,
        aiTier: Int? = nil,
        challengeService: MatchChallengeService? = nil
    ) {
        let ai = aiTier.map(AIOpponent.withTier) ?? AIOpponent.random()
        self.opponent = ai
        self.onlineConfig = onlineMatch
        self.challengeService = challengeService
        self.isFriendGame = isFriendGame || onlineMatch != nil
        self.aiAfterMatchmakingTimeout = aiAfterMatchmakingTimeout || aiTier != nil
        self.aiBingosRemaining = onlineMatch == nil ? AIOpponent.bingoQuota(for: ai.tier) : 0
        if let onlineMatch {
            self.opponentName = onlineMatch.opponentUsername
            self.opponentBadgeStats = BadgeStats()
        } else {
            self.opponentName = opponentName ?? ai.username
            self.opponentBadgeStats = BadgeCatalog.aiStats(tier: ai.tier)
        }
        if let seed = onlineMatch?.seed {
            self.seed = SeededRandom(string: seed)
        }
    }

    // MARK: - Match flow

    func startMatch() {
        phase = .searching
        if isOnlineMatch {
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                phase = .matchupIntro
                try? await Task.sleep(for: .seconds(2.8))
                guard !Task.isCancelled else { return }
                beginRound()
            }
        } else {
            // Explicit Play AI — short beat, no fake matchmaking wait.
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                phase = .matchupIntro
                try? await Task.sleep(for: .seconds(2.8))
                guard !Task.isCancelled else { return }
                beginRound()
            }
        }
    }

    func beginRound() {
        typedWord = ""
        lockedWord = nil
        lockedAt = nil
        playerSatOut = false
        opponentHasSubmitted = false
        roundEnding = false
        submissionFeedback = nil
        secondsLeft = GameConstants.roundSeconds
        if let onlineConfig {
            rack = OnlineMatchConfig.pvpRack(
                seed: onlineConfig.seed,
                round: roundNumber,
                tieReplay: consecutiveTies)
            opponentPlan = (nil, 99)
        } else {
            rack = WordDictionary.shared.makeRack(size: GameConstants.pvpRackSize, rng: &seed)
            let allowBingo = shouldAIPlayBingoThisRound()
            var plan = opponent.play(rack: rack, allowBingo: allowBingo)
            // Never sit out — if somehow empty, take any buildable word.
            if plan.word == nil {
                plan.word = WordDictionary.shared.buildableWords(from: rack).first
            }
            if let word = plan.word, word.count >= rack.count {
                aiBingosRemaining = max(0, aiBingosRemaining - 1)
            }
            opponentPlan = plan
        }

        if roundNumber == 1 {
            startFlipSequence()
        } else {
            phase = .intro
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                startFlipSequence()
            }
        }
    }

    /// Spend the match bingo budget across rounds instead of front-loading.
    private func shouldAIPlayBingoThisRound() -> Bool {
        guard aiBingosRemaining > 0 else { return false }
        if opponent.tier >= 10 { return true }
        let expectedTotalRounds = 7
        let roundsLeft = max(1, expectedTotalRounds - rounds.count)
        if aiBingosRemaining >= roundsLeft { return true }
        return Double.random(in: 0...1) < Double(aiBingosRemaining) / Double(roundsLeft)
    }

    private func startFlipSequence() {
        phase = .flipping
        SoundPlayer.shared.play(.whoosh)
        Task {
            // Slide in (~0.75s) + pause, then flip face-up.
            try? await Task.sleep(for: .seconds(RackView.slideTotalDuration + 0.5))
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
                    if remaining <= 5 && remaining > 0 {
                        SoundPlayer.shared.play(.tick)
                        haptics.impact()
                    }
                }
                if !opponentHasSubmitted && elapsed >= opponentPlan.submitAt && opponentPlan.word != nil {
                    opponentHasSubmitted = true
                    checkBothSubmitted()
                }
                if isOnlineMatch {
                    await pollOpponentSubmission()
                }
                if elapsed >= Double(GameConstants.roundSeconds) {
                    endRound()
                    return
                }
            }
        }
    }

    /// Player taps Submit. Invalid words are rejected with feedback so the
    /// player can keep trying; only real, buildable words lock in. A submission
    /// is final — once a valid word is locked it can't be changed, and the round
    /// ends as soon as both players have locked a word in.
    func submitWord() {
        guard phase == .playing, let start = roundStart else { return }
        guard lockedWord == nil else { return }   // already submitted; no resubmits
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
        lockedAt = Date().timeIntervalSince(start)
        haptics.impact()
        if let onlineConfig, let challengeService {
            let roundKey = GameConstants.submissionRoundKey(
                displayRound: roundNumber, tieReplay: consecutiveTies)
            let ms = Int((lockedAt ?? 0) * 1000)
            Task {
                await challengeService.submitWord(
                    matchId: onlineConfig.matchId,
                    roundKey: roundKey,
                    word: word,
                    submittedMs: ms)
            }
        }
        checkBothSubmitted()
    }

    private func pollOpponentSubmission() async {
        guard !opponentHasSubmitted,
              let onlineConfig,
              let challengeService else { return }
        let roundKey = GameConstants.submissionRoundKey(
            displayRound: roundNumber, tieReplay: consecutiveTies)
        let sub = await challengeService.fetchOpponentSubmission(
            matchId: onlineConfig.matchId,
            roundKey: roundKey,
            opponentUserId: onlineConfig.opponentUserId)
        guard let word = sub.word else { return }
        opponentPlan = (word, sub.submittedAt ?? Double(GameConstants.roundSeconds))
        opponentHasSubmitted = true
        checkBothSubmitted()
    }

    /// Rearranges the player's own tiles to help spot words. Purely local — the
    /// opponent never sees your shuffle — and cosmetic (order never affects
    /// validity or scoring).
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

    /// Once both players have locked in, there's nothing left to do (no
    /// resubmits), so end the round early after a short beat for feedback.
    private func checkBothSubmitted() {
        guard phase == .playing, !roundEnding else { return }
        guard lockedWord != nil, opponentHasSubmitted else { return }
        roundEnding = true
        timerTask?.cancel()
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            guard phase == .playing else { return }
            endRound()
        }
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

        if isOnlineMatch, !opponentHasSubmitted {
            Task {
                await pollOpponentSubmission()
                finishEndRound()
            }
            return
        }
        finishEndRound()
    }

    private func finishEndRound() {
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
            rack: rack.map(String.init),
            player: player,
            opponent: opp,
            outcome: outcome,
            wasTieReplay: consecutiveTies > 0,
            displayRound: roundNumber,
            attempt: consecutiveTies + 1)
        rounds.append(result)
        lastRound = result
        onRoundScored?(result)

        switch outcome {
        case .playerWins:
            playerRoundWins += 1
            consecutiveTies = 0
            SoundPlayer.shared.play(.win)
        case .opponentWins:
            opponentRoundWins += 1
            consecutiveTies = 0
            SoundPlayer.shared.play(.lose)
        case .tie:
            consecutiveTies += 1
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
        phase = .searching
        // AI "accepts" after a believable delay.
        Task {
            try? await Task.sleep(for: .seconds(Double.random(in: 1.0...3.0)))
            beginRound()
        }
    }

    /// Player chose to leave mid-match. Cements the current round standings into
    /// a final result (leader wins, else a tie) and records it.
    func exitEarly() {
        guard phase != .matchOver else { return }
        timerTask?.cancel()
        let outcome: MatchOutcome
        if playerRoundWins > opponentRoundWins { outcome = .playerWins }
        else if opponentRoundWins > playerRoundWins { outcome = .opponentWins }
        else { outcome = .tie }
        finishMatch(outcome)
    }

    func cancel() {
        timerTask?.cancel()
    }
}
