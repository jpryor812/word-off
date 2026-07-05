import SwiftUI

struct MatchView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var engine: MatchEngine
    @FocusState private var inputFocused: Bool
    @State private var outOfLives = false
    @State private var topWordsByRound: [Int: (score: Int, words: [String])] = [:]
    @State private var topWordsRevealed = false
    @State private var revealBusy = false

    init(onlineMatch: OnlineMatchConfig? = nil, challengeService: MatchChallengeService? = nil) {
        _engine = StateObject(wrappedValue: MatchEngine(
            onlineMatch: onlineMatch,
            challengeService: challengeService))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch engine.phase {
            case .searching:
                searchingView
            case .matchupIntro:
                matchupIntroView
            case .intro:
                roundIntro
            case .flipping, .go, .playing:
                gameBoard
            case .reveal, .transition:
                revealView
            case .matchOver:
                matchOverView
            }
        }
        .onAppear {
            engine.onMatchComplete = { record in
                app.statsStore.record(match: record)
                app.badgeStore.recordMatchComplete(
                    outcome: record.outcome,
                    playerRoundWins: record.playerRoundWins,
                    opponentRoundWins: record.opponentRoundWins,
                    totalRounds: record.rounds.count,
                    todayWins: app.statsStore.todayRecord.wins,
                    winStreak: app.statsStore.winStreak)
            }
            engine.onRoundScored = { round in
                let rack = round.rack.compactMap { $0.first }
                app.badgeStore.recordPvPRound(
                    rack: rack,
                    playerWord: round.player.word,
                    playerBreakdown: round.player.breakdown)
            }
            engine.startMatch()
        }
        .task {
            if engine.isOnlineMatch,
               let stats = await app.badgeStore.fetchStats(forUsername: engine.opponentName) {
                engine.opponentBadgeStats = stats
            }
        }
        .onDisappear { engine.cancel() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                engine.playerLeftApp()
            }
        }
        .alert("Out of lives!", isPresented: $outOfLives) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No lives left for a rematch today. Come back tomorrow or go Premium for unlimited games.")
        }
    }

    // MARK: - Searching

    private var searchingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.6)
                .tint(.white)
            Text(engine.isOnlineMatch ? "Connecting to \(engine.opponentName)…" : "Finding an opponent…")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(.white)
            Button("Cancel") { dismiss() }
                .foregroundColor(Theme.subtleText)
        }
    }

    // MARK: - Matchup intro

    private var matchupIntroView: some View {
        MatchupIntroView(
            playerName: app.username,
            opponentName: engine.opponentName,
            playerBadges: app.badgeStore.featuredBadges(
                loginStreak: app.lives.loginStreak,
                dailyStreak: app.lives.dailyCompletionStreak),
            opponentBadges: BadgeCatalog.featured(
                from: engine.opponentBadgeStats,
                loginStreak: engine.opponentBadgeStats.loginStreakBest,
                dailyStreak: engine.opponentBadgeStats.dailyStreakBest))
    }

    // MARK: - Round intro

    private var roundIntro: some View {
        VStack(spacing: 12) {
            scoreHeader
            Spacer()
            Text("ROUND \(engine.roundNumber)")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .transition(.scale.combined(with: .opacity))
            if engine.rounds.last?.outcome == .tie {
                Text("TIE! Replay — no repeat words!")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(Theme.accent)
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Game board

    private var gameBoard: some View {
        VStack(spacing: 16) {
            scoreHeader

            timerView

            Spacer()

            if engine.phase == .go {
                Text("GO!")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundColor(Theme.accent)
                    .transition(.scale)
            }

            RackView(rack: engine.rack, flipped: engine.phase != .flipping, tileSize: 38)
                .animation(.spring(duration: 0.5), value: engine.rack)
                .animation(.spring(duration: 0.5), value: engine.phase)

            if engine.phase == .playing && engine.lockedWord == nil {
                Button {
                    engine.shuffleRack()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 18)
                        .background(Capsule().fill(Theme.backgroundLight))
                }
                .padding(.top, 4)
            }

            Spacer()

            inputArea
        }
        .padding()
        .onChange(of: engine.phase) { _, newPhase in
            if newPhase == .playing { inputFocused = true }
        }
    }

    private var scoreHeader: some View {
        HStack {
            scorePill(name: app.username, wins: engine.playerRoundWins, highlight: true)
            Spacer()
            Text("Rd \(engine.roundNumber)/7")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundColor(Theme.subtleText)
            Spacer()
            scorePill(name: engine.opponentName, wins: engine.opponentRoundWins, highlight: false)
        }
    }

    private func scorePill(name: String, wins: Int, highlight: Bool) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .lineLimit(1)
                .foregroundColor(highlight ? Theme.accent : .white)
            Text("\(wins)")
                .font(.system(.title2, design: .rounded).weight(.black))
                .foregroundColor(.white)
        }
        .frame(width: 110)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.backgroundLight))
    }

    private var timerView: some View {
        ZStack {
            Circle()
                .stroke(Theme.backgroundLight, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(engine.secondsLeft) / CGFloat(GameConstants.roundSeconds))
                .stroke(
                    engine.secondsLeft <= 5 ? Theme.lose : Theme.accent,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: engine.secondsLeft)
            Text("\(engine.secondsLeft)")
                .font(.system(.title, design: .rounded).weight(.black))
                .foregroundColor(.white)
        }
        .frame(width: 72, height: 72)
    }

    private var inputArea: some View {
        VStack(spacing: 10) {
            if let locked = engine.lockedWord {
                Text("Locked in: \(locked)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.win)
                if !engine.opponentHasSubmitted {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.85)
                            .tint(Theme.accent)
                        Text("Waiting for opponent…")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(Theme.subtleText)
                    }
                } else {
                    Text("Both locked in — scoring round…")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.accent)
                }
            } else if engine.opponentHasSubmitted {
                Text("\(engine.opponentName) has submitted!")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.accent)
            }
            if let feedback = engine.submissionFeedback {
                Text(feedback)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.lose)
                    .transition(.opacity)
            }
            HStack {
                TextField("Type your word…", text: $engine.typedWord)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($inputFocused)
                    .disabled(engine.phase != .playing || engine.lockedWord != nil)
                    .onSubmit { engine.submitWord() }
                    .onChange(of: engine.typedWord) { _, _ in
                        engine.submissionFeedback = nil
                    }
                Button("Submit") { engine.submitWord() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(engine.phase != .playing || engine.typedWord.isEmpty || engine.lockedWord != nil)
            }
        }
    }

    // MARK: - Reveal

    private var revealView: some View {
        VStack(spacing: 20) {
            scoreHeader
            Spacer()
            if let round = engine.lastRound {
                RoundRevealCard(
                    round: round,
                    playerName: app.username,
                    opponentName: engine.opponentName)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer()
        }
        .padding()
        .animation(.spring(duration: 0.6), value: engine.lastRound)
    }

    // MARK: - Match over

    private var matchOverView: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(outcomeTitle)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(outcomeColor)
                    .padding(.top, 40)

                Text("\(engine.playerRoundWins) – \(engine.opponentRoundWins) vs \(engine.opponentName)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundColor(.white)

                VStack(spacing: 8) {
                    ForEach(Array(engine.rounds.enumerated()), id: \.offset) { index, round in
                        HStack {
                            Text("R\(index + 1)")
                                .font(.system(.caption, design: .rounded).weight(.black))
                                .foregroundColor(Theme.tileText.opacity(0.5))
                                .frame(width: 32)
                            Text(round.player.isValid ? (round.player.word ?? "—") : "—")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundColor(Theme.tileText)
                            Text("\(round.player.score)")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundColor(Theme.tileText.opacity(0.7))
                            Spacer()
                            Text("\(round.opponent.score)")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundColor(Theme.tileText.opacity(0.7))
                            Text(round.opponent.isValid ? (round.opponent.word ?? "—") : "—")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundColor(Theme.tileText)
                            outcomeIcon(round.outcome)
                        }
                    }
                }
                .panel()

                topWordsSection

                ShareLink(item: shareText) {
                    Label("Share Result", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.backgroundLight))

                Button {
                    requestRematch()
                } label: {
                    Label("Rematch", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(PrimaryButtonStyle())
                .opacity(engine.isOnlineMatch ? 0 : 1)
                .disabled(engine.isOnlineMatch)

                Button("Back to Home") { dismiss() }
                    .foregroundColor(Theme.subtleText)
                    .padding(.bottom, 30)
            }
            .padding()
        }
        .background(Theme.background)
    }

    private var outcomeTitle: String {
        switch engine.matchOutcome {
        case .playerWins: return "YOU WIN!"
        case .opponentWins: return "YOU LOSE"
        case .tie: return "IT'S A TIE"
        case nil: return ""
        }
    }

    private var outcomeColor: Color {
        switch engine.matchOutcome {
        case .playerWins: return Theme.win
        case .opponentWins: return Theme.lose
        default: return .white
        }
    }

    private func outcomeIcon(_ outcome: RoundOutcome) -> some View {
        Image(systemName: outcome == .playerWins ? "checkmark.circle.fill"
              : outcome == .opponentWins ? "xmark.circle.fill" : "equal.circle.fill")
            .foregroundColor(outcome == .playerWins ? Theme.win
                             : outcome == .opponentWins ? Theme.lose : .gray)
            .font(.caption)
    }

    private var shareText: String {
        var lines = ["Worded \(outcomeTitle) \(engine.playerRoundWins)–\(engine.opponentRoundWins)"]
        for (index, round) in engine.rounds.enumerated() {
            let blurred = String(repeating: "▮", count: round.player.word?.count ?? 1)
            let marker = round.outcome == .playerWins ? "✅" : round.outcome == .opponentWins ? "❌" : "➖"
            lines.append("R\(index + 1): \(blurred) \(round.player.score) pts \(marker)")
        }
        lines.append("Play me at worded.app")
        return lines.joined(separator: "\n")
    }

    // MARK: - Top words reveal ($0.99 or free for premium)

    @ViewBuilder
    private var topWordsSection: some View {
        if topWordsRevealed {
            VStack(alignment: .leading, spacing: 10) {
                Label("Best possible words", systemImage: "trophy.fill")
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText)
                ForEach(Array(engine.rounds.enumerated()), id: \.offset) { index, _ in
                    if let solution = topWordsByRound[index] {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Round \(index + 1)")
                                    .font(.system(.caption, design: .rounded).weight(.black))
                                    .foregroundColor(Theme.tileText.opacity(0.5))
                                Spacer()
                                Text("\(solution.score) pts")
                                    .font(.system(.caption, design: .rounded).weight(.black))
                                    .foregroundColor(Theme.accentDark)
                            }
                            FlowLayout(spacing: 6) {
                                ForEach(solution.words, id: \.self) { word in
                                    Text(word)
                                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                                        .foregroundColor(Theme.tileText)
                                        .lineLimit(1)
                                        .fixedSize()
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 9)
                                        .background(Capsule().fill(Theme.tileFace))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .panel()
        } else {
            Button {
                Task { await revealTopWords() }
            } label: {
                if revealBusy {
                    ProgressView().tint(.white)
                } else {
                    Label(revealButtonTitle, systemImage: "trophy.fill")
                }
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.accentDark))
            .disabled(revealBusy)
        }
    }

    private var revealButtonTitle: String {
        if app.entitlements.isPremium { return "Reveal Top Words" }
        let price = app.entitlements.matchRevealProduct?.displayPrice ?? "$0.99"
        return "Reveal Top Words · \(price)"
    }

    private func revealTopWords() async {
        revealBusy = true
        defer { revealBusy = false }

        if !app.entitlements.isPremium {
            let purchased = await app.entitlements.purchaseMatchReveal()
            guard purchased else { return }
        }

        let rounds = engine.rounds
        let solutions = await Task.detached(priority: .userInitiated) {
            var result: [Int: (score: Int, words: [String])] = [:]
            for (index, round) in rounds.enumerated() {
                let rack = round.rack.compactMap { $0.first }
                result[index] = DailySolver.bestWords(from: rack)
            }
            return result
        }.value

        topWordsByRound = solutions
        topWordsRevealed = true
    }

    private func requestRematch() {
        // Rematch costs a life for free users (both players must accept in
        // online play; vs AI it always accepts).
        if app.entitlements.isPremium || app.lives.consumeLife() {
            engine.rematch()
        } else {
            outOfLives = true
        }
    }
}

struct RoundRevealCard: View {
    let round: RoundResult
    let playerName: String
    let opponentName: String

    var body: some View {
        VStack(spacing: 16) {
            Text(roundBanner)
                .font(.system(.title2, design: .rounded).weight(.black))
                .foregroundColor(bannerColor)

            submissionRow(
                name: playerName,
                submission: round.player,
                isWinner: round.outcome == .playerWins,
                isFaster: playerIsFaster)
            Divider()
            submissionRow(
                name: opponentName,
                submission: round.opponent,
                isWinner: round.outcome == .opponentWins,
                isFaster: !playerIsFaster && opponentHasTime)
        }
        .panel()
    }

    /// Whichever valid submission came in with the lower elapsed time is faster.
    private var playerIsFaster: Bool {
        let p = round.player.isValid ? round.player.submittedAt : nil
        let o = round.opponent.isValid ? round.opponent.submittedAt : nil
        switch (p, o) {
        case let (.some(pt), .some(ot)): return pt <= ot
        case (.some, .none): return true
        default: return false
        }
    }

    private var opponentHasTime: Bool {
        round.opponent.isValid && round.opponent.submittedAt != nil
    }

    private var roundBanner: String {
        switch round.outcome {
        case .playerWins: return "You take the round!"
        case .opponentWins: return "\(opponentName) takes it!"
        case .tie: return "Tied! Replay!"
        }
    }

    private var bannerColor: Color {
        switch round.outcome {
        case .playerWins: return Theme.win
        case .opponentWins: return Theme.lose
        case .tie: return Theme.accentDark
        }
    }

    private func submissionRow(name: String, submission: PlayerSubmission, isWinner: Bool, isFaster: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText.opacity(0.6))
                if let word = submission.word, submission.isValid {
                    HStack(spacing: 3) {
                        ForEach(Array(word.enumerated()), id: \.offset) { _, letter in
                            TileView(letter: letter, size: 28)
                        }
                    }
                } else if submission.word != nil {
                    Text("\(submission.word!) — not a word!")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.lose)
                } else {
                    Text("No word")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(Theme.tileText.opacity(0.4))
                }
                if submission.isValid, let seconds = submission.submittedAt {
                    speedPill(seconds: seconds, isFaster: isFaster)
                }
            }
            Spacer()
            scoreDisplay(submission: submission, isWinner: isWinner)
        }
        .overlay(alignment: .topTrailing) {
            if isWinner {
                Image(systemName: "crown.fill")
                    .foregroundColor(Theme.accent)
                    .offset(y: -8)
            }
        }
    }

    /// Wind-speed style pill: shows how long the word took, in blue if this
    /// player beat their opponent to the punch (and earned the speed bonus).
    private func speedPill(seconds: TimeInterval, isFaster: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "wind")
                .font(.system(size: 11, weight: .bold))
            if isFaster {
                Text("Speed Bonus!")
                    .font(.system(.caption2, design: .rounded).weight(.black))
            }
            Text(String(format: "%.2fs", seconds))
                .font(.system(.caption2, design: .rounded).weight(.black))
                .monospacedDigit()
        }
        .foregroundColor(isFaster ? .white : Theme.tileText.opacity(0.6))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            Capsule().fill(isFaster ? Theme.speed : Theme.tileText.opacity(0.08))
        )
    }

    /// Score readout. With a speed bonus it reads like "5 + 1 = 6": the base
    /// letter score in black, the +1 speed bonus in blue, and the final total
    /// in green (with the crown) when this player won the round.
    private func scoreDisplay(submission: PlayerSubmission, isWinner: Bool) -> some View {
        let total = submission.score
        let speedBonus = submission.breakdown?.speedBonus ?? 0
        let base = total - speedBonus
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            if submission.isValid && speedBonus > 0 {
                Text("\(base)")
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText)
                Text("+")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText.opacity(0.45))
                Text("\(speedBonus)")
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundColor(Theme.speed)
                Text("=")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText.opacity(0.45))
            }
            Text("\(total)")
                .font(.system(.title, design: .rounded).weight(.black))
                .foregroundColor(isWinner ? Theme.win : Theme.tileText)
        }
    }
}
