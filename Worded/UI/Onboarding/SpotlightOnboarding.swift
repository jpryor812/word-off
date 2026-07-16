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
            focusRing: focusRing && store.isHomeSectionFocusRing(section),
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
        onSkip: @escaping () -> Void,
        onLivesIntroDone: @escaping () -> Void = {}
    ) -> some View {
        overlayPreferenceValue(OnboardingAnchorPreferenceKey.self) { anchorMap in
            GeometryReader { proxy in
                if store.isActive || store.isLivesIntroActive {
                    let arrowRects = anchorMap.mapValues { proxy[$0] }
                    HomeOnboardingOverlay(
                        store: store,
                        arrowTargets: arrowRects,
                        isPremium: isPremium,
                        onNext: onNext,
                        onSkip: onSkip,
                        onLivesIntroDone: onLivesIntroDone)
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
        // Give the six-letter row an extra beat so its anchor is available
        // before the callout tries to sit underneath it.
        let delay = store.step == .startSixLetterDaily
            ? OnboardingStore.stepTransitionDelayMs + 200
            : OnboardingStore.stepTransitionDelayMs
        Task {
            try? await Task.sleep(for: .milliseconds(delay))
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
    var onLivesIntroDone: () -> Void = {}

    var body: some View {
        ZStack {
            if store.isLivesIntroActive {
                if store.blocksHomeInteraction {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                }
                LivesIntroCallout(
                    focusRect: arrowTargets[.livesCard],
                    isVisible: store.livesIntroPhase == .showingCallout,
                    onDone: onLivesIntroDone)
            } else if store.step == .homePlayFreely {
                HomeWelcomeOverlay(onContinue: onNext, onSkip: onSkip)
            } else if store.step == .twoWaysToPlay {
                if store.blocksHomeInteraction {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                }
                TwoWaysToPlayCallout(
                    isVisible: !store.isStepTransitioning,
                    onNext: onNext,
                    onSkip: onSkip)
            } else if store.step == .startSixLetterDaily {
                if store.blocksHomeInteraction {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                }
                AnchoredOnboardingCallout(
                    step: .startSixLetterDaily,
                    isPremium: isPremium,
                    focusRect: arrowTargets[.sixLetterDaily],
                    placement: .belowMidScreen,
                    showsNext: false,
                    isVisible: !store.isStepTransitioning,
                    onNext: onNext,
                    onSkip: onSkip)
            } else if store.isOnHomeTour {
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
                        showsNext: true,
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

/// First tour card: two play modes at a glance.
private struct TwoWaysToPlayCallout: View {
    var isVisible: Bool
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if isVisible {
                    VStack(spacing: 12) {
                        // Sit in the upper-middle so the card isn't buried under the fold.
                        Color.clear.frame(height: max(geo.safeAreaInsets.top + 56, geo.size.height * 0.16))
                        VStack(spacing: 18) {
                            Text("Step \(OnboardingStep.twoWaysToPlay.stepNumber) of \(OnboardingStep.count)")
                                .font(.system(.caption2, design: .rounded).weight(.black))
                                .foregroundColor(Theme.tileText.opacity(0.5))
                                .frame(maxWidth: .infinity)

                            Text("There are two ways to play Worded")
                                .font(.system(.title3, design: .rounded).weight(.black))
                                .foregroundColor(Theme.tileText)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)

                            HStack(alignment: .top, spacing: 12) {
                                modeLabel(
                                    title: "Online quickfire games",
                                    systemImage: "bolt.fill")
                                modeLabel(
                                    title: "Solo Daily Challenges",
                                    systemImage: "calendar")
                            }

                            Button("Next", action: onNext)
                                .buttonStyle(PrimaryButtonStyle())
                        }
                        .padding(20)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                        .frame(maxWidth: min(geo.size.width - 32, 360))
                        Spacer(minLength: 0)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
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

    private func modeLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.accentDark)
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundColor(Theme.tileText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Contextual teach after the first life-consuming online game.
private struct LivesIntroCallout: View {
    let focusRect: CGRect?
    var isVisible: Bool
    var onDone: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if isVisible {
                    VStack(spacing: 12) {
                        if let focusRect, focusRect.width > 1,
                           geo.size.height - focusRect.maxY > 200 {
                            Color.clear.frame(height: focusRect.maxY + 12)
                            Image(systemName: "arrowtriangle.up.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Theme.panel)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            calloutCard
                                .frame(maxWidth: min(geo.size.width - 32, 360))
                            Spacer(minLength: max(geo.safeAreaInsets.bottom, 16))
                        } else {
                            Spacer(minLength: 0)
                            calloutCard
                                .frame(maxWidth: min(geo.size.width - 32, 360))
                                .padding(.bottom, max(geo.safeAreaInsets.bottom, 16) + 8)
                        }
                    }
                    .frame(width: geo.size.width)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isVisible)
    }

    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Lives")
                .font(.system(.title3, design: .rounded).weight(.black))
                .foregroundColor(Theme.tileText)
            Text("Online games use one life each. You get 5 per day — log in 2 days in a row for +1 bonus life (up to +5 at a 10-day streak). Daily challenges never cost a life. Premium or a Day Pass unlocks unlimited play.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(Theme.tileText.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Button("Got it", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
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
                    case .belowMidScreen:
                        calloutBelowMidScreen(in: geo)
                    case .belowFocus:
                        if let focusRect, focusRect.width > 1, focusRect.height > 1 {
                            calloutBelowFocus(focusRect: focusRect, in: geo)
                        } else {
                            // Anchor can lag a frame after scroll — never leave the step blank.
                            calloutPinnedBottom(in: geo)
                        }
                    case .aboveFocus:
                        if let focusRect, focusRect.width > 1, focusRect.height > 1 {
                            calloutAboveFocus(focusRect: focusRect, in: geo)
                        } else {
                            calloutPinnedBottom(in: geo)
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
    private func calloutBelowMidScreen(in geo: GeometryProxy) -> some View {
        // Flexible on every phone: 65% from top / 35% from bottom.
        let centerY = geo.size.height * 0.65
        let cardWidth = min(geo.size.width - 32, 360)

        VStack(spacing: gap) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 18))
                .foregroundColor(Theme.panel)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            calloutCard
                .frame(maxWidth: cardWidth)
        }
        .padding(.horizontal, 16)
        .position(x: geo.size.width / 2, y: centerY)
        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
    }

    @ViewBuilder
    private func calloutBelowFocus(focusRect: CGRect, in geo: GeometryProxy) -> some View {
        // Keep the card tucked under the focused control; clamp so it still fits on-screen.
        let reservedForCard: CGFloat = 220
        let maxTop = max(geo.size.height - reservedForCard - max(geo.safeAreaInsets.bottom, 16), 80)
        let preferredTop = focusRect.maxY > 0 && focusRect.minY < geo.size.height
            ? focusRect.maxY + gap
            : geo.size.height * 0.42
        let topPad = min(preferredTop, maxTop)

        VStack(spacing: gap) {
            Color.clear.frame(height: topPad)
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 18))
                .foregroundColor(Theme.panel)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            calloutCard
                .frame(maxWidth: min(geo.size.width - 32, 360))
            Spacer(minLength: max(geo.safeAreaInsets.bottom, 16))
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
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
            } else if step == .startSixLetterDaily {
                Text("Tap the 6-letter daily above")
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
        case .twoWaysToPlay: return ""
        case .startSixLetterDaily: return "Let's play your first daily challenge"
        case .dailyLeaderboard: return "Global Leaderboard"
        case .dailyPremiumPitch: return "Top Words & Premium"
        case .quickMatch: return "Play Online"
        case .inviteFriend: return "Challenge a Friend"
        case .homePlayFreely: return ""
        }
    }

    private var bodyText: String {
        switch step {
        case .twoWaysToPlay:
            return ""
        case .startSixLetterDaily:
            return "Four rounds of 24 seconds each to build the highest scoring points possible."
        case .dailyLeaderboard:
            return "Check out how you performed against other players around the world."
        case .dailyPremiumPitch:
            return "And if you're dying to know what the correct words were, you can become a premium member to find out the top words for each round in each daily challenge, and access unlimited online games."
        case .quickMatch:
            return "Play against another player from around the world in a quickfire best of 7 series."
        case .inviteFriend:
            return "Challenge a friend by username or invite them via text. Your first friend game each day is free — it won't use a life."
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
                    Text("We're happy you're here!")
                        .font(.system(.title3, design: .rounded).weight(.black))
                        .foregroundColor(Theme.tileText)
                    Text("Feel free to finish out the daily challenges or play someone online.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(Theme.tileText.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Close", action: onContinue)
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
