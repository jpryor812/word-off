import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var showMatch = false
    @State private var showFriendSheet = false
    @State private var showPaywall = false
    @State private var showStats = false
    @State private var outOfLivesAlert = false
    @State private var challengeError: String?
    @State private var challengingUsername: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        livesBar
                        playCard
                        DailyHubView(showPaywall: $showPaywall)
                        statsCard
                    }
                    .padding(16)
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(item: $app.onlineMatchToStart) { config in
                MatchView(onlineMatch: config, challengeService: app.challengeService)
                    .environmentObject(app)
            }
            .fullScreenCover(isPresented: $showMatch) {
                MatchView()
                    .environmentObject(app)
            }
            .sheet(isPresented: $showFriendSheet) {
                FriendChallengeSheet(
                    busy: app.isWaitingForChallengeAccept,
                    errorMessage: challengeError
                ) { username in
                    challengingUsername = username
                    Task { await sendChallenge(to: username) }
                }
                .environmentObject(app)
            }
            .onChange(of: app.pendingChallengeUsername) { _, name in
                guard let name, !name.isEmpty else { return }
                challengingUsername = name
                showFriendSheet = true
                app.pendingChallengeUsername = nil
            }
            .overlay {
                if app.isWaitingForChallengeAccept, let name = challengingUsername {
                    ChallengeWaitingOverlay(
                        opponentName: name,
                        invite: app.pendingInviteChallenge,
                        challengerUsername: app.username,
                        onCancel: {
                            Task { await app.cancelOutgoingChallenge() }
                            challengingUsername = nil
                        })
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(app)
            }
            .sheet(isPresented: $showStats) {
                StatsView().environmentObject(app)
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-demo-match") {
                    showMatch = true
                }
                if ProcessInfo.processInfo.arguments.contains("-demo-paywall") {
                    showPaywall = true
                }
                #endif
            }
            .onChange(of: app.challengeService.outgoingChallenge) { _, _ in
                app.handleOutgoingChallengeUpdate()
            }
            .onChange(of: app.challengeStatusMessage) { _, message in
                if let message { challengeError = message }
            }
            .alert(
                "Game Challenge",
                isPresented: Binding(
                    get: { app.challengeService.incomingChallenge != nil },
                    set: { _ in }
                ),
                presenting: app.challengeService.incomingChallenge
            ) { invite in
                Button("Accept") {
                    Task { await app.acceptIncomingChallenge() }
                }
                Button("Decline", role: .destructive) {
                    Task { await app.rejectIncomingChallenge() }
                }
            } message: { invite in
                Text("\(invite.challengerUsername) is challenging you to a game!")
            }
            .alert("Out of lives!", isPresented: $outOfLivesAlert) {
                Button("Get Unlimited") { showPaywall = true }
                Button("OK", role: .cancel) {}
            } message: {
                Text("You've used all your games for today. Come back tomorrow, keep your login streak going for bonus lives, or go Premium for unlimited play.")
            }
        }
    }

    private func sendChallenge(to username: String) async {
        challengeError = nil
        let canPlay = app.entitlements.isPremium
            || app.lives.livesRemaining > 0
            || app.lives.hasFreeFriendGame
        guard canPlay else {
            showFriendSheet = false
            outOfLivesAlert = true
            return
        }
        do {
            try await app.sendFriendChallenge(to: username)
            if !app.entitlements.isPremium {
                _ = app.lives.consumeLife(isFriendGame: true)
            }
            showFriendSheet = false
        } catch {
            challengeError = error.localizedDescription
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("WORDED")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Hey, \(app.username)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(Theme.subtleText)
            }
            Spacer()
            Button {
                showStats = true
            } label: {
                Image(systemName: "chart.bar.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(Theme.backgroundLight))
            }
        }
        .padding(.top, 8)
    }

    private var livesBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                if app.entitlements.isPremium {
                    Label("Unlimited games", systemImage: "infinity")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.tileText)
                } else {
                    HStack(spacing: 4) {
                        ForEach(0..<app.lives.totalLivesToday, id: \.self) { index in
                            Image(systemName: index < app.lives.livesRemaining ? "heart.fill" : "heart")
                                .foregroundColor(Theme.lose)
                                .font(.subheadline)
                        }
                    }
                }
                Spacer()
            }

            Divider().overlay(Theme.tileEdge.opacity(0.35))

            loginStreakTracker
        }
        .panel()
    }

    private var loginStreakTracker: some View {
        let streak = min(app.lives.loginStreak, 10)
        let bonusEarned = app.lives.bonusLives

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(app.lives.loginStreak) day streak", systemImage: "flame.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.black))
                    .foregroundColor(Theme.accentDark)
                Spacer()
                if !app.entitlements.isPremium {
                    Text("+\(bonusEarned) bonus \(bonusEarned == 1 ? "life" : "lives")")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.tileText.opacity(0.65))
                }
            }

            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { index in
                    let day = index + 1
                    if index.isMultiple(of: 2) {
                        loginDayCircle(filled: streak >= day)
                    } else {
                        loginHeartCircle(earned: streak >= day)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Text("Get one extra life every 2 days in a row that you log in. Log in 10 days in a row and get five extra lives.")
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loginDayCircle(filled: Bool) -> some View {
        Circle()
            .strokeBorder(filled ? Theme.win : Theme.tileEdge.opacity(0.5), lineWidth: 1.5)
            .background(Circle().fill(filled ? Theme.win.opacity(0.25) : Theme.tileFace.opacity(0.45)))
            .frame(width: 22, height: 22)
            .overlay {
                if filled {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(Theme.win)
                }
            }
    }

    private func loginHeartCircle(earned: Bool) -> some View {
        Circle()
            .strokeBorder(earned ? Theme.lose.opacity(0.6) : Theme.tileEdge.opacity(0.5), lineWidth: 1.5)
            .background(Circle().fill(earned ? Theme.lose.opacity(0.15) : Theme.tileFace.opacity(0.45)))
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: earned ? "heart.fill" : "heart")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(earned ? Theme.lose : Theme.tileEdge.opacity(0.45))
            }
    }

    private var playCard: some View {
        VStack(spacing: 12) {
            Text("QUICK MATCH")
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText)
            Text("7 rounds · \(GameConstants.roundSeconds) seconds each · first to 4 wins")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.7))

            quickMatchStats

            Button {
                startQuickMatch()
            } label: {
                Label("Play Online", systemImage: "bolt.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                showFriendSheet = true
            } label: {
                Label(
                    app.lives.hasFreeFriendGame && !app.entitlements.isPremium
                        ? "Challenge a Friend (free today!)"
                        : "Challenge a Friend",
                    systemImage: "person.2.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.backgroundLight))
        }
        .panel()
    }

    private var quickMatchStats: some View {
        let record = app.statsStore.todayRecord
        let streak = app.statsStore.winStreak
        let hint = BadgeCatalog.nextBadgeHint(todayWins: record.wins, winStreak: streak)

        return VStack(spacing: 10) {
            HStack {
                Text("Today: \(record.wins)–\(record.losses)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText)
                Spacer()
                if streak > 0 {
                    Label("\(streak) win streak", systemImage: "flame.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.accentDark)
                } else {
                    Text("No active streak")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(Theme.tileText.opacity(0.5))
                }
            }

            if let hint {
                nextBadgeHintRow(hint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.45)))
    }

    private func nextBadgeHintRow(_ hint: BadgeProgress) -> some View {
        let progress = Double(hint.current) / Double(hint.nextThreshold)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: hint.kind.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(BadgeTier.color(for: hint.nextThreshold))
                Text("Next badge: \(hint.kind.label)")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText.opacity(0.7))
                Spacer()
                Text("\(hint.current)/\(hint.nextThreshold)")
                    .font(.system(.caption, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText)
            }
            Text(hint.label)
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.55))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.tileEdge.opacity(0.35))
                    Capsule()
                        .fill(BadgeTier.color(for: hint.nextThreshold))
                        .frame(width: geo.size.width * min(1, progress))
                }
            }
            .frame(height: 6)
        }
    }

    private var statsCard: some View {
        let stats = app.statsStore.stats
        return HStack {
            statBlock(value: "\(stats.wins)", label: "Wins")
            statBlock(value: "\(stats.losses)", label: "Losses")
            statBlock(value: String(format: "%.1f", stats.averageWordScore), label: "Avg Word")
            statBlock(value: String(format: "%.1f", stats.pointsPerSecond),
                      label: "Pts/Sec", icon: "wind", color: Theme.speed)
        }
        .panel()
    }

    private func statBlock(value: String, label: String, icon: String? = nil, color: Color = Theme.tileText) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(color)
                }
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.black))
                    .foregroundColor(color)
            }
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func startQuickMatch() {
        if app.entitlements.isPremium || app.lives.consumeLife() {
            showMatch = true
        } else {
            outOfLivesAlert = true
        }
    }
}

struct ChallengeWaitingOverlay: View {
    let opponentName: String
    let invite: MatchChallengeInvite?
    let challengerUsername: String
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)
                Text("Waiting for \(opponentName)…")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
                Text("They'll get a challenge in the app, or send them a text invite below.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(Theme.subtleText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let invite {
                    ShareLink(
                        item: ChallengeInviteLink.shareMessage(
                            challengerUsername: challengerUsername,
                            challengeId: invite.id),
                        subject: Text("Worded challenge"),
                        message: Text("Let's play Worded!")
                    ) {
                        Label("Send Text Invite", systemImage: "message.fill")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(Capsule().fill(Theme.accent))
                    }
                }

                Button("Cancel Challenge", role: .cancel, action: onCancel)
                    .foregroundColor(Theme.subtleText)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.backgroundLight))
            .padding(32)
        }
    }
}

struct FriendChallengeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppState
    @State private var username = ""
    var busy: Bool
    var errorMessage: String?
    var onChallenge: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 18) {
                    Text("Challenge a friend by username. They must be signed in and have the app open to accept.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    TextField("Friend's username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(busy)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundColor(Theme.lose)
                            .multilineTextAlignment(.center)
                    }

                    Button("Send Challenge") {
                        onChallenge(username.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(username.count < 3 || busy)

                    ShareLink(
                        item: ChallengeInviteLink.profileShareMessage(username: app.username),
                        subject: Text("Play Worded with me")
                    ) {
                        Label("Invite via Text", systemImage: "message.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.backgroundLight))

                    Text("Your first friend game each day is free — it won't use a life.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(Theme.subtleText)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
