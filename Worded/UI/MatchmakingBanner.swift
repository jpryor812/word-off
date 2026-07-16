import SwiftUI

/// Compact top strip for background quick-match search / match-found.
struct MatchmakingBanner: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        switch app.matchmakingBanner {
        case .hidden:
            EmptyView()
        case .searching:
            bannerChrome(accent: Theme.accent) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                        Text("Searching for a player…")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        Button {
                            app.cancelQuickMatchSearch()
                        } label: {
                            Text("Cancel")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.22))
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            app.presentAIDifficultyPicker()
                        } label: {
                            Text("Play AI")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundColor(Theme.background)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .matchFound(let opponent):
            bannerChrome(accent: Theme.win) {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Match found!")
                            .font(.system(.subheadline, design: .rounded).weight(.black))
                            .foregroundColor(.white)
                        Text(
                            app.isInDailyPlay
                                ? "vs \(opponent) — tap to leave daily & play"
                                : "vs \(opponent) — tap to play"
                        )
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(.white.opacity(0.9))
                    }
                    Spacer(minLength: 8)
                    Button {
                        app.dismissMatchmakingBanner()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onTapGesture {
                app.acceptMatchmakingBannerAction()
            }
        }
    }

    private func bannerChrome<Content: View>(
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Modal to pick AI difficulty 1–10 before starting a stand-in match.
struct AIDifficultyPickerOverlay: View {
    @EnvironmentObject var app: AppState
    @State private var difficulty: Double = 5

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    app.dismissAIDifficultyPicker()
                }

            VStack(spacing: 18) {
                Text("AI Difficulty")
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText)

                Text("How hard? \(Int(difficulty.rounded())) / 10")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.background)

                Slider(value: $difficulty, in: 1...10, step: 1)
                    .tint(Theme.accent)

                HStack {
                    Text("Easier")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.tileText.opacity(0.55))
                    Spacer()
                    Text("Harder")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundColor(Theme.tileText.opacity(0.55))
                }

                Button {
                    app.confirmAIDifficultyAndPlay(tier: Int(difficulty.rounded()))
                } label: {
                    Text("Play")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Cancel") {
                    app.dismissAIDifficultyPicker()
                }
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundColor(Theme.tileText.opacity(0.7))
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.panel)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            )
            .padding(.horizontal, 28)
        }
        .onAppear {
            difficulty = Double(app.selectedAIDifficulty)
        }
    }
}
