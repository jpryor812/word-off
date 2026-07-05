import SwiftUI

struct StatsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        recordCard
                        streakCard
                        badgesCard
                        dailyHistoryCard
                        matchHistoryCard
                        signOutButton
                    }
                    .padding()
                }
            }
            .navigationTitle("Your Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var recordCard: some View {
        let stats = app.statsStore.stats
        return VStack(spacing: 10) {
            Text("RECORD")
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText.opacity(0.5))
            HStack(spacing: 24) {
                stat("\(stats.wins)", "Wins", Theme.win)
                stat("\(stats.losses)", "Losses", Theme.lose)
                stat("\(stats.ties)", "Ties", .gray)
                stat(String(format: "%.1f", stats.averageWordScore), "Avg Word", Theme.accentDark)
            }
        }
        .panel()
    }

    private var streakCard: some View {
        HStack {
            Label("\(app.lives.loginStreak)-day login streak", systemImage: "flame.fill")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundColor(Theme.accentDark)
            Spacer()
            Text("+\(app.lives.bonusLives) bonus lives")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundColor(Theme.tileText)
        }
        .panel()
    }

    private var badgesCard: some View {
        let tracks = BadgeCatalog.allTracks(
            stats: app.badgeStore.stats,
            loginStreak: app.lives.loginStreak,
            dailyStreak: app.lives.dailyCompletionStreak,
            todayWins: app.statsStore.todayRecord.wins,
            winStreak: app.statsStore.winStreak)
        let earnedCount = tracks.filter(\.isMaxed).count
        let inProgress = tracks.filter { !$0.isMaxed && ($0.earnedTier != nil || $0.current > 0) }
        let notStarted = tracks.filter { !$0.isMaxed && $0.earnedTier == nil && $0.current == 0 }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BADGES")
                    .font(.system(.caption, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText.opacity(0.5))
                Spacer()
                Text("\(earnedCount + inProgress.count)/\(tracks.count) started")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.tileText.opacity(0.45))
            }

            if !inProgress.isEmpty {
                sectionHeader("In progress")
                ForEach(inProgress.sorted { $0.progressFraction > $1.progressFraction }) { track in
                    BadgeProgressRow(track: track)
                }
            }

            if !notStarted.isEmpty {
                sectionHeader("Not yet earned")
                ForEach(notStarted) { track in
                    BadgeProgressRow(track: track)
                }
            }

            let maxed = tracks.filter(\.isMaxed)
            if !maxed.isEmpty {
                sectionHeader("Completed")
                ForEach(maxed) { track in
                    BadgeProgressRow(track: track)
                }
            }
        }
        .panel()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(.caption2, design: .rounded).weight(.black))
            .foregroundColor(Theme.accentDark.opacity(0.7))
            .padding(.top, 4)
    }

    private var dailyHistoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DAILY HISTORY")
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText.opacity(0.5))
            if app.dailyStore.results.isEmpty {
                Text("No daily puzzles played yet.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(Theme.tileText.opacity(0.6))
            } else {
                ForEach(app.dailyStore.results.sorted { $0.completedAt > $1.completedAt }.prefix(15)) { result in
                    HStack {
                        Text(result.date)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(Theme.tileText.opacity(0.6))
                        Text("\(result.rackSize)-letter")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(Theme.tileText)
                        Spacer()
                        Text("\(result.totalScore) pts")
                            .font(.system(.subheadline, design: .rounded).weight(.black))
                            .foregroundColor(Theme.accentDark)
                    }
                }
            }
        }
        .panel()
    }

    private var matchHistoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENT MATCHES")
                .font(.system(.caption, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText.opacity(0.5))
            if app.statsStore.stats.matches.isEmpty {
                Text("No matches yet. Go play!")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(Theme.tileText.opacity(0.6))
            } else {
                ForEach(app.statsStore.stats.matches.prefix(15)) { match in
                    HStack {
                        Image(systemName: icon(match.outcome))
                            .foregroundColor(color(match.outcome))
                        Text("vs \(match.opponentName)")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(Theme.tileText)
                        Spacer()
                        Text("\(match.playerRoundWins)–\(match.opponentRoundWins)")
                            .font(.system(.subheadline, design: .rounded).weight(.black))
                            .foregroundColor(Theme.tileText.opacity(0.7))
                    }
                }
            }
        }
        .panel()
    }

    private var signOutButton: some View {
        Button("Sign Out") {
            app.signOut()
            dismiss()
        }
        .font(.system(.subheadline, design: .rounded).weight(.bold))
        .foregroundColor(Theme.lose)
        .padding(.top, 8)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.black))
                .foregroundColor(color)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.6))
        }
    }

    private func icon(_ outcome: MatchOutcome) -> String {
        switch outcome {
        case .playerWins: return "checkmark.circle.fill"
        case .opponentWins: return "xmark.circle.fill"
        case .tie: return "equal.circle.fill"
        }
    }

    private func color(_ outcome: MatchOutcome) -> Color {
        switch outcome {
        case .playerWins: return Theme.win
        case .opponentWins: return Theme.lose
        case .tie: return .gray
        }
    }
}
