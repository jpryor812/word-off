import SwiftUI

/// Top-of-screen Accept / Decline for challenges and friend requests.
struct SocialBanner: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if let invite = app.challengeService.incomingChallenge, !app.onboardingStore.isActive {
            bannerChrome(accent: Theme.accent) {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Challenge from \(invite.challengerUsername)")
                            .font(.system(.subheadline, design: .rounded).weight(.black))
                            .foregroundColor(.white)
                        Text("Play a match now?")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Spacer(minLength: 4)
                    actionButtons(
                        accept: { Task { await app.acceptIncomingChallenge() } },
                        decline: { Task { await app.rejectIncomingChallenge() } })
                }
            }
        } else if let request = app.friendsService.bannerRequest, !app.onboardingStore.isActive {
            bannerChrome(accent: Theme.win) {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.plus.fill")
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(request.otherUsername) wants to be friends")
                            .font(.system(.subheadline, design: .rounded).weight(.black))
                            .foregroundColor(.white)
                        Text("Accept or decline")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Spacer(minLength: 4)
                    actionButtons(
                        accept: {
                            Task {
                                try? await app.friendsService.acceptRequest(request)
                            }
                        },
                        decline: {
                            Task {
                                try? await app.friendsService.denyRequest(request)
                            }
                        },
                        onDismiss: { app.friendsService.dismissBannerRequest() })
                }
            }
        }
    }

    private func actionButtons(
        accept: @escaping () -> Void,
        decline: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Button(action: decline) {
                Text("No")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.22)))
            }
            .buttonStyle(.plain)

            Button(action: accept) {
                Text("Yes")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.background)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
            }
            .buttonStyle(.plain)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(5)
                }
                .buttonStyle(.plain)
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
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            )
            .padding(.horizontal, 12)
    }
}
