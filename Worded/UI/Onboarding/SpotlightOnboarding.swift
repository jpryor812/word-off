import SwiftUI

// MARK: - Structural dimming (opacity on siblings, not cutout overlays)

private enum OnboardingDimming {
    static let inactiveOpacity: CGFloat = 0.5
}

struct OnboardingDimmedModifier: ViewModifier {
    let isDimmed: Bool
    var showsFocusRing: Bool = false
    var focusCornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .opacity(isDimmed ? OnboardingDimming.inactiveOpacity : 1)
            .allowsHitTesting(!isDimmed)
            .overlay {
                if showsFocusRing {
                    RoundedRectangle(cornerRadius: focusCornerRadius)
                        .stroke(Theme.accent, lineWidth: 2.5)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func onboardingDimmed(
        _ isDimmed: Bool,
        focusRing: Bool = false,
        cornerRadius: CGFloat = 18
    ) -> some View {
        modifier(OnboardingDimmedModifier(
            isDimmed: isDimmed,
            showsFocusRing: focusRing,
            focusCornerRadius: cornerRadius))
    }

    func homeOnboardingSection(
        _ store: OnboardingStore,
        section: HomeOnboardingFocus,
        focusRing: Bool = true,
        cornerRadius: CGFloat = 18
    ) -> some View {
        onboardingDimmed(
            store.isHomeSectionDimmed(section),
            focusRing: focusRing && store.isHomeSectionFocused(section),
            cornerRadius: cornerRadius)
    }

    func dailyResultOnboardingSection(
        _ store: OnboardingStore,
        section: DailyResultOnboardingFocus,
        focusRing: Bool = true,
        cornerRadius: CGFloat = 18
    ) -> some View {
        onboardingDimmed(
            store.isDailyResultDimmed(section),
            focusRing: focusRing && !store.isDailyResultDimmed(section),
            cornerRadius: cornerRadius)
    }
}

// MARK: - Arrow anchors (position only)

struct OnboardingAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [HomeOnboardingAnchor: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [HomeOnboardingAnchor: Anchor<CGRect>],
        nextValue: () -> [HomeOnboardingAnchor: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct DailyResultOnboardingAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [DailyResultOnboardingAnchor: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [DailyResultOnboardingAnchor: Anchor<CGRect>],
        nextValue: () -> [DailyResultOnboardingAnchor: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    func onboardingAnchor(_ id: HomeOnboardingAnchor) -> some View {
        anchorPreference(key: OnboardingAnchorPreferenceKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }

    func dailyResultOnboardingAnchor(_ id: DailyResultOnboardingAnchor) -> some View {
        anchorPreference(key: DailyResultOnboardingAnchorPreferenceKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }
}

extension View {
    func homeOnboardingSpotlight(
        store: OnboardingStore,
        isPremium: Bool,
        onNext: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) -> some View {
        overlayPreferenceValue(OnboardingAnchorPreferenceKey.self) { anchorMap in
            GeometryReader { proxy in
                if store.isActive {
                    let arrowRects = anchorMap.mapValues { proxy[$0] }
                    HomeOnboardingOverlay(
                        store: store,
                        arrowTargets: arrowRects,
                        isPremium: isPremium,
                        onNext: onNext,
                        onSkip: onSkip)
                }
            }
        }
    }

    func dailyResultOnboardingSpotlight(
        store: OnboardingStore,
        onNext: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) -> some View {
        overlayPreferenceValue(DailyResultOnboardingAnchorPreferenceKey.self) { anchorMap in
            GeometryReader { proxy in
                if store.isInDailyResultsOnboarding {
                    let arrowRects = anchorMap.mapValues { proxy[$0] }
                    DailyResultOnboardingOverlay(
                        store: store,
                        arrowTargets: arrowRects,
                        onNext: onNext,
                        onSkip: onSkip)
                }
            }
        }
    }
}

// MARK: - Scroll + reveal sequencing

enum OnboardingScroll {
    @MainActor
    static func scrollToStep(
        store: OnboardingStore,
        proxy: ScrollViewProxy,
        animated: Bool = true
    ) {
        guard store.isActive, let target = store.scrollTargetID else { return }
        store.beginStepTransition()
        let anchor = store.scrollAnchor
        if animated {
            withAnimation(.easeInOut(duration: 0.45)) {
                proxy.scrollTo(target, anchor: anchor)
            }
        } else {
            proxy.scrollTo(target, anchor: anchor)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(OnboardingStore.stepTransitionDelayMs))
            await MainActor.run {
                store.finishStepTransition()
            }
        }
    }
}

// MARK: - Home overlay

struct HomeOnboardingOverlay: View {
    @ObservedObject var store: OnboardingStore
    let arrowTargets: [HomeOnboardingAnchor: CGRect]
    let isPremium: Bool
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        ZStack {
            if store.step == .homePlayFreely {
                HomeWelcomeOverlay(onContinue: onNext, onSkip: onSkip)
            } else if store.isOnHomeTour || store.step == .startFiveLetterDaily {
                if store.blocksHomeInteraction {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                }

                if let step = store.step {
                    AnchoredOnboardingCallout(
                        step: step,
                        isPremium: isPremium,
                        focusRect: store.homeFocusSectionAnchor.flatMap { arrowTargets[$0] },
                        placement: store.calloutPlacement,
                        showsNext: step != .startFiveLetterDaily,
                        isVisible: !store.isStepTransitioning,
                        onNext: onNext,
                        onSkip: onSkip)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(store.step == .homePlayFreely ? .isModal : [])
    }
}

struct DailyResultOnboardingOverlay: View {
    @ObservedObject var store: OnboardingStore
    let arrowTargets: [DailyResultOnboardingAnchor: CGRect]
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        ZStack {
            if store.step == .dailyLeaderboard {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
            }

            if let step = store.step {
                AnchoredOnboardingCallout(
                    step: step,
                    isPremium: false,
                    focusRect: store.dailyResultArrowAnchor.flatMap { arrowTargets[$0] },
                    placement: store.calloutPlacement,
                    showsNext: step == .dailyLeaderboard,
                    isVisible: !store.isStepTransitioning,
                    onNext: onNext,
                    onSkip: onSkip)
            }
        }
    }
}

// MARK: - Callout anchored below the focused component

private struct AnchoredOnboardingCallout: View {
    let step: OnboardingStep
    let isPremium: Bool
    let focusRect: CGRect?
    let placement: OnboardingCalloutPlacement
    var showsNext: Bool
    var isVisible: Bool
    var onNext: () -> Void
    var onSkip: () -> Void

    private let gap: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if isVisible {
                    switch placement {
                    case .pinnedBottom:
                        calloutPinnedBottom(in: geo)
                    case .belowFocus:
                        if let focusRect, focusRect.width > 1 {
                            calloutBelowFocus(focusRect: focusRect, in: geo)
                        }
                    case .aboveFocus:
                        if let focusRect, focusRect.width > 1 {
                            calloutAboveFocus(focusRect: focusRect, in: geo)
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .overlay(alignment: .topTrailing) {
            Button("Skip tour", action: onSkip)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundColor(.white.opacity(0.85))
                .padding(.top, 12)
                .padding(.trailing, 16)
                .opacity(isVisible ? 1 : 0)
        }
    }

    @ViewBuilder
    private func calloutBelowFocus(focusRect: CGRect, in geo: GeometryProxy) -> some View {
        let spaceBelow = geo.size.height - focusRect.maxY
        let fitsBelow = spaceBelow > 200

        if fitsBelow {
            VStack(spacing: gap) {
                Color.clear.frame(height: focusRect.maxY + gap)
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.panel)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                calloutCard
                    .frame(maxWidth: min(geo.size.width - 32, 360))
                Spacer(minLength: max(geo.safeAreaInsets.bottom, 16))
            }
            .frame(width: geo.size.width)
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                calloutCard
                    .frame(maxWidth: min(geo.size.width - 32, 360))
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 16) + 8)
            }
            .frame(width: geo.size.width)
        }
    }

    @ViewBuilder
    private func calloutAboveFocus(focusRect: CGRect, in geo: GeometryProxy) -> some View {
        let topInset = max(geo.safeAreaInsets.top + 52, 16)
        let visibleFocusTop = max(focusRect.minY, topInset)
        let anchorY = visibleFocusTop - gap
        let reservedBelowFocus = max(geo.size.height - anchorY, 0)
        let maxBlockHeight = max(anchorY - topInset, 72)
        let arrowHeight: CGFloat = 18
        let maxCardHeight = max(maxBlockHeight - gap - arrowHeight, 48)
        let cardWidth = min(geo.size.width - 32, 360)

        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            Spacer(minLength: 0)
            VStack(spacing: gap) {
                ScrollView(showsIndicators: false) {
                    calloutCard
                        .frame(maxWidth: cardWidth)
                }
                .frame(maxWidth: cardWidth, maxHeight: maxCardHeight)
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.panel)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            }
            .frame(maxWidth: cardWidth, maxHeight: maxBlockHeight)
            Color.clear.frame(height: reservedBelowFocus)
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
    }

    @ViewBuilder
    private func calloutPinnedBottom(in geo: GeometryProxy) -> some View {
        VStack(spacing: gap) {
            Spacer(minLength: 0)
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 18))
                .foregroundColor(Theme.panel)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            calloutCard
                .frame(maxWidth: min(geo.size.width - 32, 360))
        }
        .padding(.bottom, max(geo.safeAreaInsets.bottom, 16) + 8)
        .frame(width: geo.size.width, height: geo.size.height)
    }

    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Step \(step.stepNumber) of \(OnboardingStep.count)")
                .font(.system(.caption2, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText.opacity(0.5))
            if !title.isEmpty {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundColor(Theme.tileText)
            }
            Text(bodyText)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            if showsNext {
                Button("Next", action: onNext)
                    .buttonStyle(PrimaryButtonStyle())
            } else if step == .dailyPremiumPitch {
                Text("Tap Reveal Top Words above")
                    .font(.system(.caption, design: .rounded).weight(.black))
                    .foregroundColor(Theme.accentDark)
            } else if step == .startFiveLetterDaily {
                Text("Tap the 5-letter daily above")
                    .font(.system(.caption, design: .rounded).weight(.black))
                    .foregroundColor(Theme.accentDark)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }

    private var title: String {
        switch step {
        case .quickMatch: return "Play Online"
        case .lives: return "Your Lives"
        case .dailies: return "Daily Challenges"
        case .inviteFriend: return "Challenge a Friend"
        case .dailyLeaderboard: return "Global Leaderboard"
        case .dailyPremiumPitch: return "Top Words & Premium"
        case .startFiveLetterDaily: return "Let's play your first daily challenge"
        case .homePlayFreely: return ""
        }
    }

    private var bodyText: String {
        switch step {
        case .quickMatch:
            return "Play against another player from around the world in a quickfire best of 7 series."
        case .lives:
            if isPremium {
                return "Each online game costs one life. You start with 5 lives and can unlock more by logging in multiple days in a row, or by becoming a premium member."
            }
            return "Free players get 5 games per day. Log in 2 days in a row for +1 bonus life (up to +5 at a 10-day streak). Daily challenges never cost a life. Premium or a Day Pass unlocks unlimited play."
        case .dailies:
            return "Complete up to 6 puzzles each day and see how your score stacks up against the rest of the world. This is a four round game where the best scores win!"
        case .inviteFriend:
            return "Challenge a friend by username or invite them via text. Your first friend game each day is free — it won't use a life."
        case .dailyLeaderboard:
            return "Check out how you performed against other players around the world."
        case .dailyPremiumPitch:
            return "And if you're dying to know what the correct words were, you can become a premium member to find out the top words for each round in each daily challenge, and access unlimited online games."
        case .startFiveLetterDaily:
            return "This will only take 1–2 minutes."
        case .homePlayFreely:
            return ""
        }
    }
}

struct HomeWelcomeOverlay: View {
    var onContinue: () -> Void
    var onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip tour", action: onSkip)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Step \(OnboardingStep.homePlayFreely.stepNumber) of \(OnboardingStep.count)")
                        .font(.system(.caption2, design: .rounded).weight(.black))
                        .foregroundColor(Theme.tileText.opacity(0.5))
                    Text("You're all set!")
                        .font(.system(.title3, design: .rounded).weight(.black))
                        .foregroundColor(Theme.tileText)
                    Text("Now feel free to play online or complete the daily challenge to compete to be the best!")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(Theme.tileText.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Let's go!", action: onContinue)
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                .frame(maxWidth: 360)
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Friend challenge (sheet)

struct FriendChallengeContent: View {
    @EnvironmentObject var app: AppState
    @Binding var username: String
    let busy: Bool
    let errorMessage: String?
    var onChallenge: (String) -> Void
    var showsLocalModeNote: Bool = true

    var body: some View {
        VStack(spacing: 18) {
            Text("Challenge a friend by username, or invite them via text.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            if showsLocalModeNote && app.isLocalMode {
                Text("Sign in for in-app challenges. Text invites still work.")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(Theme.accent)
                    .multilineTextAlignment(.center)
            }

            TextField("Friend's username", text: $username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(busy || app.isLocalMode)

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
            .disabled(username.count < 3 || busy || app.isLocalMode)

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
        }
    }
}

struct OnboardingInviteCard: View {
    @EnvironmentObject var app: AppState
    @State private var username = ""
    var errorMessage: String?
    var onChallenge: (String) -> Void
    var onDismiss: () -> Void
    var onInviteSent: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Challenge a Friend")
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .foregroundColor(.white)
                Spacer()
                ExitGameButton(action: onDismiss)
                    .accessibilityLabel("Dismiss invite tour")
            }
            .padding(.bottom, 12)

            FriendChallengeContent(
                username: $username,
                busy: app.isWaitingForChallengeAccept,
                errorMessage: errorMessage,
                onChallenge: onChallenge)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.backgroundLight))
        .padding(.horizontal, 24)
    }
}
