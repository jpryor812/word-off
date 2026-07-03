import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var showMatch = false
    @State private var showFriendSheet = false
    @State private var showPaywall = false
    @State private var showStats = false
    @State private var friendUsername: String?
    @State private var outOfLivesAlert = false

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
            .fullScreenCover(isPresented: $showMatch) {
                MatchView(friendUsername: friendUsername)
                    .environmentObject(app)
            }
            .sheet(isPresented: $showFriendSheet) {
                FriendChallengeSheet { username in
                    friendUsername = username
                    showFriendSheet = false
                    startFriendGame(username: username)
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
                // Demo hooks for automated screenshots / smoke tests.
                if ProcessInfo.processInfo.arguments.contains("-demo-match") {
                    friendUsername = nil
                    showMatch = true
                }
                #endif
            }
            .alert("Out of lives!", isPresented: $outOfLivesAlert) {
                Button("Get Unlimited") { showPaywall = true }
                Button("OK", role: .cancel) {}
            } message: {
                Text("You've used all your games for today. Come back tomorrow, keep your login streak going for bonus lives, or go Premium for unlimited play.")
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("WORD-OFF!")
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
            Label("\(app.lives.loginStreak) day streak", systemImage: "flame.fill")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundColor(Theme.accentDark)
        }
        .panel()
    }

    private var playCard: some View {
        VStack(spacing: 12) {
            Text("QUICK MATCH")
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText)
            Text("7 rounds · 20 seconds each · first to 4 wins")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.7))
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

    private var statsCard: some View {
        let stats = app.statsStore.stats
        return HStack {
            statBlock(value: "\(stats.wins)", label: "Wins")
            statBlock(value: "\(stats.losses)", label: "Losses")
            statBlock(value: String(format: "%.1f", stats.averageWordScore), label: "Avg Word")
        }
        .panel()
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func startQuickMatch() {
        if app.entitlements.isPremium || app.lives.consumeLife() {
            friendUsername = nil
            showMatch = true
        } else {
            outOfLivesAlert = true
        }
    }

    private func startFriendGame(username: String) {
        if app.entitlements.isPremium || app.lives.consumeLife(isFriendGame: true) {
            showMatch = true
        } else {
            outOfLivesAlert = true
        }
    }
}

struct FriendChallengeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    var onChallenge: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 18) {
                    Text("Challenge a friend by username, or send them an invite link.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    TextField("Friend's username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Send Challenge") {
                        onChallenge(username)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(username.count < 3)

                    ShareLink(
                        item: URL(string: "https://wordoff.app/invite")!,
                        message: Text("Play me in Word-Off! Download the app and challenge me: ")
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
