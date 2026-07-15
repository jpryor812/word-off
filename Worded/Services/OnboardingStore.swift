import Foundation
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case quickMatch = 0
    case lives = 1
    case dailies = 2
    case inviteFriend = 3
    case startFiveLetterDaily = 4
    case dailyLeaderboard = 5
    case dailyPremiumPitch = 6
    case homePlayFreely = 7

    var stepNumber: Int { rawValue + 1 }
    static var count: Int { allCases.count }
}

enum HomeOnboardingAnchor: Hashable {
    case quickMatchCard
    case livesCard
    case dailyHubCard
    case playOnline
    case challengeFriend
    case fiveLetterDaily
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
}

/// Versioned first-run tour over the real Home screen.
@MainActor
final class OnboardingStore: ObservableObject {
    static let currentVersion = 3
    /// Set to `false` before shipping — when true, onboarding runs every Home launch and never saves completion.
    static let repeatEveryLaunchForTesting = true
    private static let completedKey = "worded.onboarding.completedVersion"

    @Published private(set) var step: OnboardingStep?
    @Published private(set) var isActive = false
    @Published private(set) var awaitingDailyResultsOnboarding = false
    @Published private(set) var isStepTransitioning = false

    static let stepTransitionDelayMs = 450
    /// Pause on the results screen before dimming and scrolling to the leaderboard step.
    static let dailyResultsRevealDelayMs = 1000

    var shouldShow: Bool {
        if Self.repeatEveryLaunchForTesting { return true }
        return UserDefaults.standard.integer(forKey: Self.completedKey) < Self.currentVersion
    }

    var isInDailyResultsOnboarding: Bool {
        step == .dailyLeaderboard || step == .dailyPremiumPitch
    }

    var isOnHomeTour: Bool {
        isActive && step != nil && step != .homePlayFreely && !isInDailyResultsOnboarding
    }

    func isHomeSectionFocused(_ section: HomeOnboardingFocus) -> Bool {
        guard let step else { return true }
        switch (step, section) {
        case (.quickMatch, .quickMatch), (.inviteFriend, .quickMatch): return true
        case (.lives, .lives): return true
        case (.dailies, .dailyHub), (.startFiveLetterDaily, .dailyHub): return true
        default: return false
        }
    }

    func isHomeSectionDimmed(_ section: HomeOnboardingFocus) -> Bool {
        guard isOnHomeTour, !isStepTransitioning else { return false }
        return !isHomeSectionFocused(section)
    }

    func isDailyRowDimmed(rackSize: Int) -> Bool {
        guard step == .startFiveLetterDaily, !isStepTransitioning else { return false }
        return rackSize != 5
    }

    func isDailyRowFocused(rackSize: Int) -> Bool {
        step == .startFiveLetterDaily && rackSize == 5
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
        switch step {
        case .quickMatch, .inviteFriend: return .quickMatchCard
        case .lives: return .livesCard
        case .dailies: return .dailyHubCard
        case .startFiveLetterDaily: return .fiveLetterDaily
        default: return nil
        }
    }

    /// Anchor used only for drawing pointer arrows — not for dimming regions.
    var homeArrowAnchor: HomeOnboardingAnchor? {
        switch step {
        case .quickMatch: return .playOnline
        case .inviteFriend: return .challengeFriend
        case .startFiveLetterDaily: return .fiveLetterDaily
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
    }

    func startIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reset-onboarding") {
            resetForDebug()
        }
        #endif
        guard shouldShow, !isActive else { return }
        isActive = true
        if Self.repeatEveryLaunchForTesting {
            step = .quickMatch
            return
        }
        let completed = UserDefaults.standard.integer(forKey: Self.completedKey)
        step = completed < Self.currentVersion ? .quickMatch : nil
        if step == nil { isActive = false }
    }

    /// User tapped the 5-letter daily row during the forced-start step.
    func beganFiveLetterDaily() {
        guard step == .startFiveLetterDaily else { return }
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
        case .dailyLeaderboard:
            step = .dailyPremiumPitch
        case .dailyPremiumPitch:
            break
        case .homePlayFreely:
            complete()
        default:
            guard let next = OnboardingStep(rawValue: current.rawValue + 1) else { return }
            step = next
        }
    }

    /// Paywall or top-words sheet dismissed after the premium pitch step.
    func finishDailyOnboardingAndReturnHome() {
        guard step == .dailyPremiumPitch else { return }
        awaitingDailyResultsOnboarding = false
        step = .homePlayFreely
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
        case .quickMatch: return "onboarding.playOnline"
        case .lives: return "onboarding.lives"
        case .dailies: return "onboarding.dailies"
        case .inviteFriend: return "onboarding.playOnline"
        case .startFiveLetterDaily: return "onboarding.fiveLetterDaily"
        case .dailyLeaderboard: return "onboarding.dailyLeaderboard"
        case .dailyPremiumPitch: return "onboarding.revealTopWords"
        case .homePlayFreely, nil: return nil
        }
    }

    var scrollAnchor: UnitPoint {
        switch step {
        case .dailies, .dailyLeaderboard: return .bottom
        case .startFiveLetterDaily: return .top
        default: return .top
        }
    }

    var calloutPlacement: OnboardingCalloutPlacement {
        switch step {
        case .dailies, .startFiveLetterDaily: return .pinnedBottom
        case .dailyLeaderboard: return .aboveFocus
        default: return .belowFocus
        }
    }

    var blocksHomeInteraction: Bool {
        guard let step else { return false }
        return step != .startFiveLetterDaily
    }
}
