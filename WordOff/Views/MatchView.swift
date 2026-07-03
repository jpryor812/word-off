import SwiftUI

struct MatchView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var engine: MatchEngine
    @FocusState private var inputFocused: Bool
    @State private var outOfLives = false

    init(friendUsername: String? = nil) {
        _engine = StateObject(wrappedValue: MatchEngine(
            opponentName: friendUsername,
            isFriendGame: friendUsername != nil))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch engine.phase {
            case .searching:
                searchingView
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
            }
            engine.startMatch()
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
            Text("Finding an opponent…")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(.white)
            Button("Cancel") { dismiss() }
                .foregroundColor(Theme.subtleText)
        }
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

            RackView(rack: engine.rack, flipped: engine.phase != .flipping, tileSize: 36)
                .animation(.spring(duration: 0.5), value: engine.phase)

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
            if engine.opponentHasSubmitted {
                Text("\(engine.opponentName) has submitted!")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.accent)
            }
            if let locked = engine.lockedWord {
                Text("Locked in: \(locked)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.win)
            }
            HStack {
                TextField("Type your word…", text: $engine.typedWord)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($inputFocused)
                    .disabled(engine.phase != .playing)
                    .onSubmit { engine.submitWord() }
                Button("Submit") { engine.submitWord() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(engine.phase != .playing || engine.typedWord.isEmpty)
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
        var lines = ["Word-Off! \(outcomeTitle) \(engine.playerRoundWins)–\(engine.opponentRoundWins)"]
        for (index, round) in engine.rounds.enumerated() {
            let blurred = String(repeating: "▮", count: round.player.word?.count ?? 1)
            let marker = round.outcome == .playerWins ? "✅" : round.outcome == .opponentWins ? "❌" : "➖"
            lines.append("R\(index + 1): \(blurred) \(round.player.score) pts \(marker)")
        }
        lines.append("Play me at wordoff.app")
        return lines.joined(separator: "\n")
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
                isWinner: round.outcome == .playerWins)
            Divider()
            submissionRow(
                name: opponentName,
                submission: round.opponent,
                isWinner: round.outcome == .opponentWins)
        }
        .panel()
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

    private func submissionRow(name: String, submission: PlayerSubmission, isWinner: Bool) -> some View {
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
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(submission.score)")
                    .font(.system(.title, design: .rounded).weight(.black))
                    .foregroundColor(isWinner ? Theme.win : Theme.tileText)
                if let breakdown = submission.breakdown, breakdown.speedBonus > 0 {
                    Text("+\(breakdown.speedBonus) speed")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(Theme.accentDark)
                }
                if let breakdown = submission.breakdown, breakdown.allLettersBonus > 0 {
                    Text("+\(breakdown.allLettersBonus) all letters!")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(Theme.accentDark)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isWinner {
                Image(systemName: "crown.fill")
                    .foregroundColor(Theme.accent)
                    .offset(y: -8)
            }
        }
    }
}
