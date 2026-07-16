import SwiftUI

/// Home-screen section listing the daily puzzles (5–10 letter racks).
struct DailyHubView: View {
    @EnvironmentObject var app: AppState
    @Binding var showPaywall: Bool
    @State private var activeDailySize: Int?
    @State private var detailResult: DailyPuzzleResult?
    @State private var topWordsResult: DailyPuzzleResult?

    private var today: String { DailySeed.todayString() }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("DAILY CHALLENGES")
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText)
                Spacer()
            }

            ForEach(GameConstants.dailyRackCounts, id: \.self) { size in
                dailyRow(size: size)
            }
        }
        .panel()
        .onboardingAnchor(.dailyHubCard)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demo-daily") {
                activeDailySize = 10
            }
            if ProcessInfo.processInfo.arguments.contains("-demo-detail") {
                detailResult = app.dailyStore.results.first
            }
            #endif
        }
        .fullScreenCover(item: $activeDailySize) { size in
            DailyPlayView(rackSize: size)
                .environmentObject(app)
        }
        .sheet(item: $detailResult) { result in
            DailyResultDetailView(result: result)
                .environmentObject(app)
        }
        .sheet(item: $topWordsResult) { result in
            DailyTopWordsView(result: result)
                .environmentObject(app)
        }
    }

    @ViewBuilder
    private func dailyRow(size: Int) -> some View {
        let played = app.dailyStore.result(day: today, rackSize: size)
        let done = played != nil
        let row = HStack {
            numberBlock(size: size, done: done)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(size)-Letter Daily")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText)
                Text(done ? "Done — \(played!.totalScore) pts · tap for results" : "4 racks · \(GameConstants.dailySeconds(forRackSize: size))s each")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(Theme.tileText.opacity(0.6))
            }
            Spacer()
            trailing(played: played)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.5)))
        .contentShape(Rectangle())
        .onTapGesture { tapDaily(size: size) }

        if size == OnboardingStore.onboardingDailyRackSize {
            row
                .id("onboarding.sixLetterDaily")
                .onboardingAnchor(.sixLetterDaily)
                .onboardingDimmed(
                    app.onboardingStore.isDailyRowDimmed(rackSize: size),
                    focusRing: app.onboardingStore.isDailyRowFocused(rackSize: size),
                    cornerRadius: 12)
        } else {
            row
                .onboardingDimmed(
                    app.onboardingStore.isDailyRowDimmed(rackSize: size),
                    focusRing: false,
                    cornerRadius: 12)
        }
    }

    /// The left-hand rack-size tile. When the puzzle is done it gets a green
    /// outline and a checkmark badge in the top corner.
    private func numberBlock(size: Int, done: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Text("\(size)")
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.tileFace))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(done ? Theme.win : Theme.tileEdge, lineWidth: done ? 2.5 : 1.5)
                )
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.win)
                    .background(Circle().fill(.white).frame(width: 14, height: 14))
                    .offset(x: 6, y: -6)
            }
        }
    }

    /// Trailing control: a chevron before playing, or a "Reveal Top Words"
    /// button once the puzzle is complete (locked for free players until the
    /// next day, where tapping offers Premium instead).
    @ViewBuilder
    private func trailing(played: DailyPuzzleResult?) -> some View {
        if let played {
            let unlocked = played.topWordsUnlocked(isPremium: app.entitlements.isPremium)
            Button {
                if unlocked {
                    topWordsResult = played
                } else {
                    showPaywall = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: unlocked ? "trophy.fill" : "lock.fill")
                    Text(unlocked ? "Reveal Top Words" : "Top Words Tomorrow")
                }
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundColor(unlocked ? Theme.accentDark : Theme.tileText.opacity(0.5))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    Capsule().fill(unlocked ? Theme.accent.opacity(0.18) : Color.black.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
        } else {
            Image(systemName: "chevron.right")
                .foregroundColor(Theme.tileText.opacity(0.4))
        }
    }

    private func tapDaily(size: Int) {
        if app.onboardingStore.step == .startSixLetterDaily {
            guard size == OnboardingStore.onboardingDailyRackSize else { return }
            app.onboardingStore.beganOnboardingDaily()
        }
        if let played = app.dailyStore.result(day: today, rackSize: size) {
            detailResult = played
            return
        }
        activeDailySize = size
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

/// Detail screen for a completed daily: your words, best word, and the
/// global leaderboard for that puzzle.
struct DailyResultDetailView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let result: DailyPuzzleResult
    var showsDoneButton = false
    var onDone: (() -> Void)?

    @State private var entries: [DailyLeaderboardEntry] = []
    @State private var isLoading = true
    @State private var showBestWords = false
    @State private var showTopWords = false
    @State private var showPaywall = false
    @State private var perfectScore: Int?
    @State private var standing: (rank: Int, total: Int)?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            summaryCard
                                .dailyResultOnboardingSection(app.onboardingStore, section: .summary, focusRing: false)
                            shareButton
                                .dailyResultOnboardingSection(app.onboardingStore, section: .share, focusRing: false)
                            revealButton
                            wordsCard
                                .dailyResultOnboardingSection(app.onboardingStore, section: .words, focusRing: false)
                            leaderboardCard
                            if showsDoneButton, !app.onboardingStore.isInDailyResultsOnboarding {
                                Button("Done") {
                                    if let onDone {
                                        onDone()
                                    } else {
                                        dismiss()
                                    }
                                }
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .foregroundColor(Theme.subtleText)
                                    .padding(.top, 4)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: app.onboardingStore.step) { _, _ in
                        guard app.onboardingStore.scrollTargetID != nil else { return }
                        OnboardingScroll.scrollToStep(
                            store: app.onboardingStore,
                            proxy: proxy)
                    }
                }
            }
            .coordinateSpace(name: DailyResultOnboardingCoordinateSpace.name)
            .dailyResultOnboardingSpotlight(
                store: app.onboardingStore,
                onNext: { app.onboardingStore.advance() },
                onSkip: { app.onboardingStore.skip() })
            .sheet(isPresented: $showTopWords, onDismiss: handlePremiumOnboardingDismiss) {
                DailyTopWordsView(result: result).environmentObject(app)
            }
            .sheet(isPresented: $showPaywall, onDismiss: handlePremiumOnboardingDismiss) {
                PaywallView().environmentObject(app)
            }
            .navigationTitle("\(result.rackSize)-Letter Daily")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(app.onboardingStore.isInDailyResultsOnboarding)
                }
            }
        }
        .onAppear {
            guard app.onboardingStore.awaitingDailyResultsOnboarding else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(OnboardingStore.dailyResultsRevealDelayMs))
                app.onboardingStore.beginDailyResultsOnboarding()
            }
        }
        .task {
            // Push the just-completed score up first so the server (and the
            // rank query below) reflect it right away.
            await app.dailyStore.syncResult(result)
            await loadLeaderboard()
            standing = await app.dailyStore.fetchStanding(
                day: result.date,
                rackSize: result.rackSize,
                score: result.totalScore)
            let day = result.date
            let size = result.rackSize
            perfectScore = await Task.detached(priority: .userInitiated) {
                DailySolver.perfectScore(day: day, rackSize: size)
            }.value
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 8) {
            Text("\(result.totalScore)")
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundColor(Theme.accentDark)
            Text("TOTAL POINTS · \(result.date)")
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText.opacity(0.5))
            if let perfectScore {
                let pct = perfectScore > 0
                    ? Int((Double(result.totalScore) / Double(perfectScore)) * 100) : 0
                Text("You: \(result.totalScore) · Best possible: \(perfectScore)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText)
                Text(pct >= 100 ? "Perfect run!" : "\(pct)% of the best common-word score")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(pct >= 100 ? Theme.win : Theme.tileText.opacity(0.55))
            }
            if let best = result.bestWord {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundColor(Theme.accent)
                    Text("Best word: \(best.word) — \(best.score) pts")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.tileText)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .panel()
    }

    private var shareButton: some View {
        ShareLink(item: result.shareText(perfectScore: perfectScore, standing: standing)) {
            Label("Share Score", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    @ViewBuilder
    private var revealButton: some View {
        let unlocked = result.topWordsUnlocked(isPremium: app.entitlements.isPremium)
        let onboardingPitch = app.onboardingStore.step == .dailyPremiumPitch
        Button {
            handleRevealTopWordsTap(unlocked: unlocked)
        } label: {
            Label("Reveal Top Words", systemImage: unlocked ? "trophy.fill" : "lock.fill")
        }
        .buttonStyle(PrimaryButtonStyle(color: unlocked && !onboardingPitch ? Theme.accent : Theme.backgroundLight))
        .disabled(app.onboardingStore.step == .dailyLeaderboard)
        .id("onboarding.revealTopWords")
        .dailyResultOnboardingAnchor(.revealTopWords)
        .dailyResultOnboardingSection(app.onboardingStore, section: .reveal, cornerRadius: 14)
    }

    private func handleRevealTopWordsTap(unlocked: Bool) {
        if app.onboardingStore.step == .dailyPremiumPitch {
            if app.entitlements.isPremium {
                showTopWords = true
            } else {
                showPaywall = true
            }
            return
        }
        if unlocked {
            showTopWords = true
        } else {
            showPaywall = true
        }
    }

    private func handlePremiumOnboardingDismiss() {
        guard app.onboardingStore.step == .dailyPremiumPitch else { return }
        app.onboardingStore.finishDailyOnboardingAndReturnHome()
    }

    private var wordsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR WORDS")
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText.opacity(0.5))
            ForEach(Array(result.roundScores.enumerated()), id: \.offset) { index, score in
                HStack {
                    Text("Rack \(index + 1)")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.tileText.opacity(0.5))
                        .frame(width: 56, alignment: .leading)
                    Text(result.words.indices.contains(index) ? (result.words[index] ?? "—") : "—")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(score > 0 ? Theme.tileText : Theme.lose)
                    Spacer()
                    Text("\(score) pts")
                        .font(.system(.subheadline, design: .rounded).weight(.black))
                        .foregroundColor(score > 0 ? Theme.accentDark : Theme.tileText.opacity(0.4))
                }
            }
        }
        .panel()
    }

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LEADERBOARD")
                    .font(.system(.caption, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText.opacity(0.5))
                Spacer()
            }
            Picker("View", selection: $showBestWords) {
                Text("Total Score").tag(false)
                Text("Top Word").tag(true)
            }
            .pickerStyle(.segmented)

            if !SupabaseConfig.isConfigured {
                emptyState("Connect a Supabase backend to see the global leaderboard.")
            } else if isLoading {
                HStack {
                    Spacer()
                    ProgressView().padding()
                    Spacer()
                }
            } else if entries.isEmpty {
                emptyState("No scores yet today — you might be first!")
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HStack {
                        Text("\(index + 1)")
                            .font(.system(.subheadline, design: .rounded).weight(.black))
                            .foregroundColor(index < 3 ? Theme.accent : Theme.tileText.opacity(0.5))
                            .frame(width: 30, alignment: .leading)
                        Text(entry.username)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(Theme.tileText)
                            .lineLimit(1)
                        Spacer()
                        if showBestWords {
                            if let word = entry.bestWord {
                                Text(word)
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .foregroundColor(Theme.tileText)
                                Text("\(entry.bestWordScore ?? 0)")
                                    .font(.system(.subheadline, design: .rounded).weight(.black))
                                    .foregroundColor(Theme.accentDark)
                            } else {
                                Text("—")
                                    .foregroundColor(Theme.tileText.opacity(0.4))
                            }
                        } else {
                            Text("\(entry.score) pts")
                                .font(.system(.subheadline, design: .rounded).weight(.black))
                                .foregroundColor(Theme.accentDark)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .panel()
        .id("onboarding.dailyLeaderboard")
        .dailyResultOnboardingAnchor(.leaderboard)
        .dailyResultOnboardingSection(app.onboardingStore, section: .leaderboard)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.system(.subheadline, design: .rounded))
            .foregroundColor(Theme.tileText.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    private func loadLeaderboard() async {
        var fetched = await app.dailyStore.fetchLeaderboard(day: result.date, rackSize: result.rackSize)
        // Guarantee the player sees their own score immediately, even if the
        // server upload hasn't propagated to the leaderboard query yet.
        if !app.username.isEmpty {
            fetched.removeAll { $0.username.caseInsensitiveCompare(app.username) == .orderedSame }
            fetched.append(DailyLeaderboardEntry(
                username: app.username,
                score: result.totalScore,
                bestWord: result.bestWord?.word,
                bestWordScore: result.bestWord?.score))
        }
        entries = fetched.sorted { $0.score > $1.score }
        isLoading = false
    }
}

/// Full-screen daily puzzle player.
struct DailyPlayView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var engine: DailyEngine
    @FocusState private var inputFocused: Bool
    @State private var completedResult: DailyPuzzleResult?
    @State private var badgeSnapshot: [BadgeTrackItem] = []
    @State private var badgeDeltas: [BadgeProgressDelta] = []
    @State private var showBadgeCelebration = false
    @State private var showExitConfirm = false

    init(rackSize: Int) {
        _engine = StateObject(wrappedValue: DailyEngine(rackSize: rackSize))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if showBadgeCelebration {
                BadgeProgressCelebrationView(deltas: badgeDeltas) {
                    dismiss()
                }
            } else {
                switch engine.phase {
                case .intro, .flipping, .go, .playing, .rackDone:
                    GeometryReader { geo in
                        playArea(in: geo.size)
                    }
                case .finished:
                    if let completedResult {
                        DailyResultDetailView(
                            result: completedResult,
                            showsDoneButton: true,
                            onDone: {
                                if badgeDeltas.isEmpty {
                                    dismiss()
                                } else {
                                    showBadgeCelebration = true
                                }
                            })
                            .environmentObject(app)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if app.matchmakingBanner != .hidden {
                MatchmakingBanner()
            }
        }
        .overlay {
            if app.showAIDifficultyPicker {
                AIDifficultyPickerOverlay()
            }
        }
        .onAppear {
            app.isInDailyPlay = true
            badgeSnapshot = app.badgeStore.currentTracks(
                loginStreak: app.lives.loginStreak,
                dailyStreak: app.lives.dailyCompletionStreak,
                todayWins: app.statsStore.todayRecord.wins,
                winStreak: app.statsStore.winStreak)
            engine.start()
        }
        .onDisappear {
            engine.cancel()
            app.handleDailyPlayDidDismiss()
        }
        .onChange(of: app.requestExitDailyPlay) { _, shouldExit in
            guard shouldExit else { return }
            // Leave daily (lock score) so the pending online/AI match can start.
            if engine.phase != .finished {
                engine.exitEarly()
                finishPuzzle()
            }
            dismiss()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active { engine.playerLeftApp() }
        }
        .onChange(of: engine.phase) { _, newPhase in
            if newPhase == .playing { inputFocused = true }
            if newPhase == .finished { finishPuzzle() }
        }
        .onChange(of: app.onboardingStore.step) { _, step in
            // After the premium pitch, tour resumes on Home with Play Online.
            if step == .quickMatch {
                dismiss()
            }
        }
        .onChange(of: app.onboardingStore.isActive) { _, active in
            if !active, engine.phase == .finished {
                dismiss()
            }
        }
        .alert("Leave daily challenge?", isPresented: $showExitConfirm) {
            Button("Leave", role: .destructive) { exitDaily() }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("Your current score will be locked in and any racks you haven't played will score zero.")
        }
    }

    private func exitDaily() {
        engine.exitEarly()
        finishPuzzle()
        dismiss()
    }

    private func playArea(in size: CGSize) -> some View {
        let tileSize = RackLayout.tileSize(letterCount: engine.rack.count, in: size)

        return VStack(spacing: 16) {
            HStack(spacing: 10) {
                ExitGameButton { showExitConfirm = true }
                Text("\(engine.rackSize)-LETTER DAILY")
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .foregroundColor(.white)
                Spacer()
                Text("Rack \(engine.rackIndex + 1)/\(GameConstants.dailyRoundsPerPuzzle)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.subtleText)
            }

            HStack(alignment: .top) {
                Label("\(engine.totalScore) pts", systemImage: "sum")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.accent)
                Spacer()
                VStack(spacing: 8) {
                    timer
                    if engine.phase == .playing && engine.lockedWord != nil {
                        Button {
                            engine.finishRoundEarly()
                        } label: {
                            Label("Finish", systemImage: "checkmark")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundColor(.white)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(Capsule().fill(Theme.win))
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.3), value: engine.lockedWord)
            }

            Spacer()

            if engine.phase == .go {
                Text("GO!")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundColor(Theme.accent)
            }

            if engine.phase == .rackDone {
                rackInterstitial
            } else {
                RackView(rack: engine.rack, flipped: engine.phase != .flipping,
                         tileSize: tileSize, wrapRows: 1)
                    .animation(.spring(duration: 0.5), value: engine.rack)
                    .animation(.spring(duration: 0.5), value: engine.phase)
            }

            if engine.phase == .playing {
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

            inputBar
        }
        .padding()
    }

    private var timer: some View {
        Text("\(engine.secondsLeft)")
            .font(.system(.title2, design: .rounded).weight(.black))
            .foregroundColor(engine.secondsLeft <= 5 ? Theme.lose : .white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(Theme.backgroundLight))
    }

    private var rackInterstitial: some View {
        VStack(spacing: 8) {
            let score = engine.roundScores.last ?? 0
            let word = engine.words.last ?? nil
            Text(score > 0 ? "+\(score) points!" : "No score")
                .font(.system(.title, design: .rounded).weight(.black))
                .foregroundColor(score > 0 ? Theme.win : Theme.lose)
            if let word {
                Text(word)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if let feedback = engine.submissionFeedback {
                Text(feedback)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.lose)
                    .transition(.opacity)
            } else if let locked = engine.lockedWord {
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
                    .onChange(of: engine.typedWord) { _, _ in
                        engine.submissionFeedback = nil
                    }
                Button("Submit") { engine.submitWord() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(engine.phase != .playing || engine.typedWord.isEmpty)
            }
        }
    }

    private func finishPuzzle() {
        let result = engine.makeResult()
        completedResult = result
        app.dailyStore.save(result)
        app.lives.recordDailyCompletion(day: engine.day)
        app.statsStore.recordDailyWords(scores: engine.roundScores)
        let day = engine.day
        let rackSize = engine.rackSize
        let words = result.words
        let roundScores = result.roundScores
        Task {
            let standing = await app.dailyStore.fetchStanding(
                day: day, rackSize: rackSize, score: result.totalScore)
            app.badgeStore.recordDailyCompletion(
                day: day,
                rackSize: rackSize,
                words: words,
                roundScores: roundScores,
                rank: standing?.rank,
                total: standing?.total,
                completedSizesToday: app.dailyStore.completedCount(day: day))
            app.badgeStore.refreshStreakBadges(
                loginStreak: app.lives.loginStreak,
                dailyStreak: app.lives.dailyCompletionStreak)
            badgeDeltas = BadgeCatalog.progressDeltas(
                before: badgeSnapshot,
                after: app.badgeStore.currentTracks(
                    loginStreak: app.lives.loginStreak,
                    dailyStreak: app.lives.dailyCompletionStreak,
                    todayWins: app.statsStore.todayRecord.wins,
                    winStreak: app.statsStore.winStreak))
        }
    }
}

/// Reveals the highest-scoring possible word(s) for each of a daily puzzle's
/// racks, alongside what the player actually played.
struct DailyTopWordsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let result: DailyPuzzleResult

    @State private var solutions: [DailySolver.RackSolution] = []
    @State private var isLoading = true

    private let maxWordsShown = 18

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView().tint(.white)
                        Text("Finding the best possible words…")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(Theme.subtleText)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            headerCard
                            ForEach(solutions) { solution in
                                rackCard(solution)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Top Words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await compute() }
    }

    private var headerCard: some View {
        VStack(spacing: 6) {
            Text("\(result.rackSize)-LETTER DAILY · \(result.date)")
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText.opacity(0.5))
            Text("Best possible plays")
                .font(.system(.title2, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText)
            Text("The highest-scoring word for each rack — see what you could have played.")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .panel()
    }

    private func rackCard(_ solution: DailySolver.RackSolution) -> some View {
        let playedRaw = result.words.indices.contains(solution.id) ? result.words[solution.id] : nil
        let playedWord = playedRaw?.replacingOccurrences(of: " ✕", with: "")
        let playedScore = result.roundScores.indices.contains(solution.id) ? result.roundScores[solution.id] : 0
        let nailedIt = playedScore >= solution.maxScore && solution.maxScore > 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RACK \(solution.id + 1)")
                    .font(.system(.caption, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText.opacity(0.5))
                Spacer()
                Text("MAX \(solution.maxScore) PTS")
                    .font(.system(.caption, design: .rounded).weight(.black))
                    .foregroundColor(Theme.accentDark)
            }

            RackView(rack: solution.rack,
                     tileSize: solution.rack.count > 10 ? 24 : solution.rack.count > 8 ? 28 : 32)

            FlowLayout(spacing: 6) {
                ForEach(solution.words.prefix(maxWordsShown), id: \.self) { word in
                    Text(word)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.tileText)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(Theme.tileFace))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if solution.words.count > maxWordsShown {
                Text("+\(solution.words.count - maxWordsShown) more tied for the top score")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(Theme.tileText.opacity(0.5))
            }

            Divider()

            HStack {
                Image(systemName: nailedIt ? "checkmark.seal.fill" : "person.fill")
                    .foregroundColor(nailedIt ? Theme.win : Theme.tileText.opacity(0.5))
                Text(nailedIt ? "You nailed it!" : "You played")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText.opacity(0.6))
                Spacer()
                Text(playedWord?.isEmpty == false ? playedWord! : "—")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(playedScore > 0 ? Theme.tileText : Theme.lose)
                Text("\(playedScore) pts")
                    .font(.system(.subheadline, design: .rounded).weight(.black))
                    .foregroundColor(playedScore > 0 ? Theme.accentDark : Theme.tileText.opacity(0.4))
            }
        }
        .panel()
    }

    private func compute() async {
        let day = result.date
        let size = result.rackSize
        let solved = await Task.detached(priority: .userInitiated) {
            DailySolver.solve(day: day, rackSize: size)
        }.value
        solutions = solved
        isLoading = false
    }
}
