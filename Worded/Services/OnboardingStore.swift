import Foundation
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    /// Home: two modes overview → jump into a daily.
    case twoWaysToPlay = 0
    case startSixLetterDaily = 1
    /// Daily results screen.
    case dailyLeaderboard = 2
    case dailyPremiumPitch = 3
    /// Back on Home after the first daily.
    case quickMatch = 4
    case inviteFriend = 5
    case homePlayFreely = 6

    var stepNumber: Int { rawValue + 1 }
    static var count: Int { allCases.count }
}

enum HomeOnboardingAnchor: Hashable {
    case quickMatchCard
    case livesCard
    case dailyHubCard
    case playOnline
    case challengeFriend
    case sixLetterDaily
}

enum HomeOnboardingFocus: Hashable {
    case header
    case lives
    case quickMatch
    case dailyHub
    case stats
}

enum DailyResultOnboardingFocus: Hashable {
    case summary
    case share
    case words
    case leaderboard
    case reveal
}

enum DailyResultOnboardingAnchor: Hashable {
    case leaderboard
    case revealTopWords
}

enum HomeOnboardingCoordinateSpace {
    static let name = "homeOnboarding"
}

enum DailyResultOnboardingCoordinateSpace {
    static let name = "dailyResultOnboarding"
}

enum OnboardingCalloutPlacement {
    case aboveFocus
    case belowFocus
    case pinnedBottom
    /// Callout centered at 65% from top / 35% from bottom.
    case belowMidScreen
}

enum LivesIntroPhase: Equatable {
    case idle
    case pending
    case zoomingIn
    case poppingHeart
    case zoomingOut
    case showingCallout
}

/// Versioned first-run tour over the real Home screen.
@MainActor
final class OnboardingStore: ObservableObject {
    static let currentVersion = 6
    /// Set to `true` only while iterating on the tour — when true, onboarding runs every Home launch.
    static let repeatEveryLaunchForTesting = false
    private static let completedKey = "worded.onboarding.completedVersion"
    private static let livesIntroCompletedKey = "worded.onboarding.livesIntroCompleted"
    private static let welcomeIntroCompletedKey = "worded.onboarding.welcomeIntroCompleted"

    @Published private(set) var step: OnboardingStep?
    @Published private(set) var isActive = false
    @Published private(set) var awaitingDailyResultsOnboarding = false
    @Published private(set) var isStepTransitioning = false
    /// True while the auth → home entrance animation is playing; delays the spotlight tour.
    @Published private(set) var isDeferringTourForHomeEntrance = false

    /// Contextual lives teach after the first life-consuming online game.
    @Published private(set) var livesIntroPhase: LivesIntroPhase = .idle
    /// Heart count shown during the intro animation (may briefly exceed livesRemaining).
    @Published private(set) var livesIntroVisualFilled: Int = 0
    /// Index of the heart currently popping away, if any.
    @Published private(set) var livesIntroPoppingIndex: Int? = nil

    static let stepTransitionDelayMs = 450
    /// Pause on the results screen before dimming and scrolling to the leaderboard step.
    static let dailyResultsRevealDelayMs = 1000

    private var livesIntroTask: Task<Void, Never>?

    var shouldShow: Bool {
        if Self.repeatEveryLaunchForTesting { return true }
        return UserDefaults.standard.integer(forKey: Self.completedKey) < Self.currentVersion
    }

    /// First-open tile animation, before sign-in. Shown once per install.
    var needsWelcomeIntro: Bool {
        !UserDefaults.standard.bool(forKey: Self.welcomeIntroCompletedKey)
    }

    func completeWelcomeIntro() {
        UserDefaults.standard.set(true, forKey: Self.welcomeIntroCompletedKey)
        objectWillChange.send()
    }

    /// Call at bootstrap so existing players who already finished onboarding skip the welcome.
    func migrateWelcomeIntroIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.welcomeIntroCompletedKey) else { return }
        guard UserDefaults.standard.integer(forKey: Self.completedKey) > 0 else { return }
        UserDefaults.standard.set(true, forKey: Self.welcomeIntroCompletedKey)
    }

    var hasCompletedLivesIntro: Bool {
        if Self.repeatEveryLaunchForTesting { return false }
        return UserDefaults.standard.bool(forKey: Self.livesIntroCompletedKey)
    }

    var isLivesIntroActive: Bool {
        switch livesIntroPhase {
        case .idle, .pending: return false
        case .zoomingIn, .poppingHeart, .zoomingOut, .showingCallout: return true
        }
    }

    var isLivesIntroZoomed: Bool {
        livesIntroPhase == .zoomingIn || livesIntroPhase == .poppingHeart
    }

    var isInDailyResultsOnboarding: Bool {
        step == .dailyLeaderboard || step == .dailyPremiumPitch
    }

    var isOnHomeTour: Bool {
        isActive && step != nil && step != .homePlayFreely && !isInDailyResultsOnboarding
    }

    func isHomeSectionFocused(_ section: HomeOnboardingFocus) -> Bool {
        if isLivesIntroActive { return section == .lives }
        guard let step else { return true }
        switch (step, section) {
        case (.twoWaysToPlay, .quickMatch), (.twoWaysToPlay, .dailyHub): return true
        case (.quickMatch, .quickMatch), (.inviteFriend, .quickMatch): return true
        case (.startSixLetterDaily, .dailyHub): return true
        default: return false
        }
    }

    func isHomeSectionFocusRing(_ section: HomeOnboardingFocus) -> Bool {
        guard isHomeSectionFocused(section) else { return false }
        // Overview card highlights both play modes without orange rings.
        if step == .twoWaysToPlay { return false }
        return true
    }

    func isHomeSectionDimmed(_ section: HomeOnboardingFocus) -> Bool {
        if isLivesIntroActive { return section != .lives }
        guard isOnHomeTour, !isStepTransitioning else { return false }
        return !isHomeSectionFocused(section)
    }

    func beginDeferredHomeEntrance() {
        isDeferringTourForHomeEntrance = true
    }

    func finishDeferredHomeEntrance() {
        guard isDeferringTourForHomeEntrance else { return }
        isDeferringTourForHomeEntrance = false
        startIfNeeded()
    }

    /// Rack size the forced first-daily step asks the player to start.
    static let onboardingDailyRackSize = 6

    func isDailyRowDimmed(rackSize: Int) -> Bool {
        guard step == .startSixLetterDaily, !isStepTransitioning else { return false }
        return rackSize != Self.onboardingDailyRackSize
    }

    func isDailyRowFocused(rackSize: Int) -> Bool {
        step == .startSixLetterDaily && rackSize == Self.onboardingDailyRackSize
    }

    func isDailyResultDimmed(_ section: DailyResultOnboardingFocus) -> Bool {
        guard isInDailyResultsOnboarding, let step, !isStepTransitioning else { return false }
        switch section {
        case .summary, .share, .words: return true
        case .leaderboard: return step != .dailyLeaderboard
        case .reveal: return step != .dailyPremiumPitch
        }
    }

    var homeFocusSectionAnchor: HomeOnboardingAnchor? {
        if isLivesIntroActive { return .livesCard }
        switch step {
        case .quickMatch, .inviteFriend: return .quickMatchCard
        case .startSixLetterDaily: return .sixLetterDaily
        default: return nil
        }
    }

    /// Anchor used only for drawing pointer arrows — not for dimming regions.
    var homeArrowAnchor: HomeOnboardingAnchor? {
        switch step {
        case .quickMatch: return .playOnline
        case .inviteFriend: return .challengeFriend
        case .startSixLetterDaily: return .sixLetterDaily
        default: return nil
        }
    }

    var dailyResultArrowAnchor: DailyResultOnboardingAnchor? {
        switch step {
        case .dailyLeaderboard: return .leaderboard
        case .dailyPremiumPitch: return .revealTopWords
        default: return nil
        }
    }

    func beginStepTransition() {
        isStepTransitioning = true
    }

    func finishStepTransition() {
        isStepTransitioning = false
    }

    func resetForDebug() {
        UserDefaults.standard.removeObject(forKey: Self.completedKey)
        UserDefaults.standard.removeObject(forKey: Self.livesIntroCompletedKey)
        UserDefaults.standard.removeObject(forKey: Self.welcomeIntroCompletedKey)
    }

    func resetForAccountDeletion() {
        livesIntroTask?.cancel()
        livesIntroTask = nil
        resetForDebug()
        isActive = false
        step = nil
        isStepTransitioning = false
        awaitingDailyResultsOnboarding = false
        isDeferringTourForHomeEntrance = false
        livesIntroPhase = .idle
        livesIntroVisualFilled = 0
        livesIntroPoppingIndex = nil
    }

    func startIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reset-onboarding") {
            resetForDebug()
        }
        #endif
        guard !isDeferringTourForHomeEntrance else { return }
        guard shouldShow, !isActive else { return }
        isActive = true
        // Hide callout/dimming for one beat so the first step doesn't flash
        // before Home finishes its initial scroll/layout.
        beginStepTransition()
        if Self.repeatEveryLaunchForTesting {
            step = .twoWaysToPlay
            return
        }
        let completed = UserDefaults.standard.integer(forKey: Self.completedKey)
        step = completed < Self.currentVersion ? .twoWaysToPlay : nil
        if step == nil {
            isStepTransitioning = false
            isActive = false
        }
    }

    /// Call when a daily life was actually deducted for an online/PvP game.
    func scheduleLivesIntro() {
        guard !hasCompletedLivesIntro else { return }
        guard livesIntroPhase == .idle else { return }
        livesIntroPhase = .pending
    }

    /// Starts the zoom → pop → explain sequence when Home is free.
    func tryStartLivesIntro(livesRemaining: Int, totalLives: Int) {
        guard livesIntroPhase == .pending else { return }
        guard !isActive else { return }
        guard totalLives > 0 else {
            completeLivesIntro()
            return
        }

        livesIntroTask?.cancel()
        let visualFilled = min(max(livesRemaining + 1, 1), totalLives)
        livesIntroVisualFilled = visualFilled
        livesIntroPoppingIndex = nil
        livesIntroPhase = .zoomingIn

        livesIntroTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, livesIntroPhase == .zoomingIn else { return }

            let popIndex = max(visualFilled - 1, 0)
            livesIntroPoppingIndex = popIndex
            livesIntroPhase = .poppingHeart

            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.2)) {
                livesIntroVisualFilled = livesRemaining
                livesIntroPoppingIndex = nil
            }

            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            livesIntroPhase = .zoomingOut

            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            livesIntroPhase = .showingCallout
        }
    }

    func completeLivesIntro() {
        livesIntroTask?.cancel()
        livesIntroTask = nil
        if !Self.repeatEveryLaunchForTesting {
            UserDefaults.standard.set(true, forKey: Self.livesIntroCompletedKey)
        }
        livesIntroPhase = .idle
        livesIntroVisualFilled = 0
        livesIntroPoppingIndex = nil
    }

    /// User tapped the onboarding daily row during the forced-start step.
    func beganOnboardingDaily() {
        guard step == .startSixLetterDaily else { return }
        awaitingDailyResultsOnboarding = true
        step = nil
    }

    /// First results screen after the onboarding daily puzzle finishes.
    func beginDailyResultsOnboarding() {
        guard awaitingDailyResultsOnboarding else { return }
        beginStepTransition()
        step = .dailyLeaderboard
    }

    func advance() {
        guard let current = step else { return }
        switch current {
        case .twoWaysToPlay:
            beginStepTransition()
            step = .startSixLetterDaily
        case .dailyLeaderboard:
            step = .dailyPremiumPitch
        case .dailyPremiumPitch:
            break
        case .quickMatch:
            beginStepTransition()
            step = .inviteFriend
        case .inviteFriend:
            beginStepTransition()
            step = .homePlayFreely
        case .homePlayFreely:
            complete()
        case .startSixLetterDaily:
            break
        }
    }

    /// Paywall or top-words sheet dismissed after the premium pitch step.
    func finishDailyOnboardingAndReturnHome() {
        guard step == .dailyPremiumPitch else { return }
        awaitingDailyResultsOnboarding = false
        beginStepTransition()
        step = .quickMatch
    }

    func skip() {
        awaitingDailyResultsOnboarding = false
        isStepTransitioning = false
        complete()
    }

    func complete() {
        awaitingDailyResultsOnboarding = false
        isStepTransitioning = false
        if !Self.repeatEveryLaunchForTesting {
            UserDefaults.standard.set(Self.currentVersion, forKey: Self.completedKey)
        }
        isActive = false
        step = nil
    }

    var anchor: HomeOnboardingAnchor? { homeArrowAnchor }

    var dailyResultAnchor: DailyResultOnboardingAnchor? { dailyResultArrowAnchor }

    var scrollTargetID: String? {
        switch step {
        case .twoWaysToPlay: return nil
        case .startSixLetterDaily: return "onboarding.sixLetterDaily"
        case .dailyLeaderboard: return "onboarding.dailyLeaderboard"
        case .dailyPremiumPitch: return "onboarding.revealTopWords"
        case .quickMatch: return "onboarding.playOnline"
        case .inviteFriend: return "onboarding.playOnline"
        case .homePlayFreely, nil: return nil
        }
    }

    var scrollAnchor: UnitPoint {
        switch step {
        case .dailyLeaderboard: return .bottom
        case .startSixLetterDaily: return .top
        default: return .top
        }
    }

    var calloutPlacement: OnboardingCalloutPlacement {
        switch step {
        case .twoWaysToPlay: return .pinnedBottom
        case .startSixLetterDaily: return .belowMidScreen
        case .dailyLeaderboard: return .aboveFocus
        default: return .belowFocus
        }
    }

    var blocksHomeInteraction: Bool {
        if isLivesIntroActive { return true }
        guard let step else { return false }
        return step != .startSixLetterDaily
    }
}
