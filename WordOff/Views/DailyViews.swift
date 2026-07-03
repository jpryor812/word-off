import SwiftUI

/// Home-screen section listing the five daily puzzles (5–9 letter racks).
struct DailyHubView: View {
    @EnvironmentObject var app: AppState
    @Binding var showPaywall: Bool
    @State private var activeDailySize: Int?
    @State private var limitAlert = false

    private var today: String { DailySeed.todayString() }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("DAILY CHALLENGES")
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText)
                Spacer()
                if !app.entitlements.isPremium {
                    Text("\(app.lives.unlockedDailySizes.count)/\(GameConstants.freeDailyPuzzlesPerDay) picked")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.tileText.opacity(0.6))
                }
            }

            ForEach(GameConstants.dailyRackCounts, id: \.self) { size in
                dailyRow(size: size)
            }

            if !app.entitlements.isPremium {
                Button {
                    showPaywall = true
                } label: {
                    Label("Unlock all 5 dailies", systemImage: "star.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.accentDark))
            }
        }
        .panel()
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demo-daily") {
                activeDailySize = 7
            }
            #endif
        }
        .fullScreenCover(item: $activeDailySize) { size in
            DailyPlayView(rackSize: size)
                .environmentObject(app)
        }
        .alert("Daily limit reached", isPresented: $limitAlert) {
            Button("Go Premium") { showPaywall = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Free players pick \(GameConstants.freeDailyPuzzlesPerDay) of the 5 daily puzzles. Get Premium or a Day Pass for all of them.")
        }
    }

    private func dailyRow(size: Int) -> some View {
        let played = app.dailyStore.result(day: today, rackSize: size)
        return Button {
            tapDaily(size: size)
        } label: {
            HStack {
                Text("\(size)")
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.tileFace))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.tileEdge, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(size)-Letter Daily")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.tileText)
                    Text(played != nil ? "Done — \(played!.totalScore) pts" : "4 racks · 20s each")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(Theme.tileText.opacity(0.6))
                }
                Spacer()
                Image(systemName: played != nil ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundColor(played != nil ? Theme.win : Theme.tileText.opacity(0.4))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.5)))
        }
        .disabled(played != nil)
    }

    private func tapDaily(size: Int) {
        guard app.dailyStore.result(day: today, rackSize: size) == nil else { return }
        if app.lives.unlockDailySize(size, isPremium: app.entitlements.isPremium) {
            activeDailySize = size
        } else {
            limitAlert = true
        }
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

/// Full-screen daily puzzle player.
struct DailyPlayView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var engine: DailyEngine
    @FocusState private var inputFocused: Bool
    @State private var standing: (rank: Int, total: Int)?

    init(rackSize: Int) {
        _engine = StateObject(wrappedValue: DailyEngine(rackSize: rackSize))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch engine.phase {
            case .intro, .flipping, .go, .playing, .rackDone:
                playArea
            case .finished:
                finishedView
            }
        }
        .onAppear { engine.start() }
        .onDisappear { engine.cancel() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active { engine.playerLeftApp() }
        }
        .onChange(of: engine.phase) { _, newPhase in
            if newPhase == .playing { inputFocused = true }
            if newPhase == .finished { finishPuzzle() }
        }
    }

    private var playArea: some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(engine.rackSize)-LETTER DAILY")
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .foregroundColor(.white)
                Spacer()
                Text("Rack \(engine.rackIndex + 1)/\(GameConstants.dailyRoundsPerPuzzle)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.subtleText)
            }

            HStack {
                Label("\(engine.totalScore) pts", systemImage: "sum")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.accent)
                Spacer()
                timer
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
                         tileSize: engine.rackSize > 7 ? 36 : 44)
                    .animation(.spring(duration: 0.5), value: engine.phase)
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

    // MARK: - Finished

    private var finishedView: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("DAILY COMPLETE!")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(Theme.accent)
                    .padding(.top, 40)

                Text("\(engine.totalScore) points")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                if let standing {
                    let percentile = max(1, 100 - Int((Double(standing.rank) / Double(standing.total)) * 100))
                    Text("\(standing.rank)/\(standing.total) · \(percentile)th percentile!")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(Theme.subtleText)
                } else if !SupabaseConfig.isConfigured {
                    Text("Connect online to see global rankings")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(Theme.subtleText)
                }

                VStack(spacing: 8) {
                    ForEach(Array(engine.roundScores.enumerated()), id: \.offset) { index, score in
                        HStack {
                            Text("Rack \(index + 1)")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundColor(Theme.tileText.opacity(0.6))
                            Text(engine.words[index] ?? "—")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundColor(Theme.tileText)
                            Spacer()
                            Text("\(score)")
                                .font(.system(.title3, design: .rounded).weight(.black))
                                .foregroundColor(score > 0 ? Theme.tileText : Theme.lose)
                        }
                    }
                }
                .panel()

                ShareLink(item: shareText) {
                    Label("Share Score", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Done") { dismiss() }
                    .foregroundColor(Theme.subtleText)
                    .padding(.bottom, 30)
            }
            .padding()
        }
        .background(Theme.background)
    }

    private var shareText: String {
        var lines = ["Word-Off! \(engine.rackSize)-Letter Daily — \(engine.totalScore) pts"]
        for (index, score) in engine.roundScores.enumerated() {
            let length = engine.words[index]?.replacingOccurrences(of: " ✕", with: "").count ?? 0
            let blurred = length > 0 ? String(repeating: "▮", count: length) : "—"
            lines.append("Rack \(index + 1): \(blurred) \(score) pts")
        }
        if let standing {
            let percentile = max(1, 100 - Int((Double(standing.rank) / Double(standing.total)) * 100))
            lines.append("\(standing.rank)/\(standing.total) · \(percentile)th percentile")
        }
        lines.append("Play today's puzzle: wordoff.app")
        return lines.joined(separator: "\n")
    }

    private func finishPuzzle() {
        let result = engine.makeResult()
        app.dailyStore.save(result)
        app.statsStore.recordDailyWords(scores: engine.roundScores)
        Task {
            standing = await app.dailyStore.fetchStanding(
                day: engine.day, rackSize: engine.rackSize, score: engine.totalScore)
        }
    }
}
