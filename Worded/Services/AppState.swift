import Foundation
import SwiftUI
import Combine
import UIKit

enum MatchmakingBannerPhase: Equatable {
    case hidden
    case searching
    case matchFound(opponentName: String)
    // case noPlayersFound // old 60s Keep waiting / Play AI chooser
    // case aiReady
}

enum BeginQuickMatchResult: Equatable {
    case started
    case outOfLives
    case alreadyBusy
    /// Local / unsigned-in mode — start AI immediately.
    case localAI
}

@MainActor
final class AppState: ObservableObject {
    @Published var isLoading = true
    @Published var session: Session?
    @Published var profile: Profile?
    @Published var username: String = UserDefaults.standard.string(forKey: "worded.username") ?? ""
    @Published var country: String = UserDefaults.standard.string(forKey: "worded.country") ?? ""

    let lives = LivesManager()
    let entitlements = EntitlementsManager()
    let dailyStore = DailyStore()
    let statsStore = StatsStore()
    let badgeStore = BadgeStore()
    let challengeService = MatchChallengeService()
    let matchmakingService = MatchmakingService()
    let onboardingStore = OnboardingStore()

    @Published var onlineMatchToStart: OnlineMatchConfig?
    @Published var challengeStatusMessage: String?
    @Published var isWaitingForChallengeAccept = false
    @Published var pendingInviteChallenge: MatchChallengeInvite?
    /// True while actively polling the matchmaking queue.
    @Published var isMatchmaking = false
    @Published var matchmakingFellBackToAI = false
    /// Compact status strip while searching / holding a found match.
    @Published var matchmakingBanner: MatchmakingBannerPhase = .hidden
    /// Human match ready but not yet started (e.g. player is in a daily).
    @Published var pendingOnlineMatch: OnlineMatchConfig?
    /// AI match waiting to start after leaving a daily (or difficulty confirm).
    @Published var pendingAIMatch = false
    /// Difficulty sheet after tapping Play AI.
    @Published var showAIDifficultyPicker = false
    @Published var selectedAIDifficulty = 5
    /// Tier for the next AI MatchView launch (nil = random).
    @Published var pendingAITier: Int?
    /// Bumped to tell Home to present an AI MatchView.
    @Published var launchAIMatchToken = 0
    /// Daily puzzle is on screen — don't auto-interrupt with a found match.
    @Published var isInDailyPlay = false
    /// Ask DailyPlayView to dismiss so a pending match can start.
    @Published var requestExitDailyPlay = false
    private var startMatchAfterDailyExit = false
    private var isAppInForeground = true
    private var matchmakingBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    private var cancellables: Set<AnyCancellable> = []
    private var pendingDeepLinkChallengeId: String?

    init() {
        // Forward child object changes so views observing AppState refresh
        // when lives, purchases, daily results, or stats change.
        for child in [lives.objectWillChange.eraseToAnyPublisher(),
                      entitlements.objectWillChange.eraseToAnyPublisher(),
                      dailyStore.objectWillChange.eraseToAnyPublisher(),
                      statsStore.objectWillChange.eraseToAnyPublisher(),
                      badgeStore.objectWillChange.eraseToAnyPublisher(),
                      challengeService.objectWillChange.eraseToAnyPublisher(),
                      matchmakingService.objectWillChange.eraseToAnyPublisher(),
                      onboardingStore.objectWillChange.eraseToAnyPublisher()] {
            child
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    /// True when running without a Supabase backend (guest/local mode).
    var isLocalMode: Bool { !SupabaseConfig.isConfigured }

    func bootstrap() async {
        WordDictionary.shared.loadIfNeeded()
        lives.registerLogin()
        badgeStore.refreshStreakBadges(
            loginStreak: lives.loginStreak,
            dailyStreak: lives.dailyCompletionStreak)
        await entitlements.refresh()
        onboardingStore.migrateWelcomeIntroIfNeeded()

        if isLocalMode {
            // Local mode: a stored username acts as the "account".
            if !username.isEmpty {
                session = Session(accessToken: "local", refreshToken: "local", userId: "local")
                profile = Profile(id: "local", username: username, country: country, isPremium: entitlements.isPremium)
            }
        } else {
            await restoreOnlineSession()
            await badgeStore.syncFromServer()
            challengeService.startPolling()
        }
        isLoading = false
        await processPendingDeepLinkIfNeeded()
    }

    private func openChallengeFromDeepLink(_ challengeId: String) async {
        guard !isLocalMode else { return }
        do {
            _ = try await challengeService.fetchChallengeForDeepLink(id: challengeId)
        } catch {
            challengeStatusMessage = error.localizedDescription
        }
    }

    @Published var pendingChallengeUsername: String?

    func processPendingDeepLinkIfNeeded() async {
        guard let challengeId = pendingDeepLinkChallengeId else { return }
        pendingDeepLinkChallengeId = nil
        await openChallengeFromDeepLink(challengeId)
    }

    func handleIncomingURL(_ url: URL) async {
        if let challengeId = ChallengeInviteLink.challengeId(from: url) {
            if session == nil || profile == nil {
                pendingDeepLinkChallengeId = challengeId
                return
            }
            await openChallengeFromDeepLink(challengeId)
            return
        }
        if let username = ChallengeInviteLink.username(from: url) {
            pendingChallengeUsername = username
        }
    }

    func challengePolling(active: Bool) {
        if active, !isLocalMode, session != nil {
            challengeService.startPolling()
        } else {
            challengeService.stopPolling()
        }
    }

    /// Starts a non-blocking quick-match search (banner stays up while browsing).
    /// Life is consumed only when a match (human or AI) actually begins.
    func beginBackgroundQuickMatch() -> BeginQuickMatchResult {
        if isMatchmaking || pendingOnlineMatch != nil || pendingAIMatch || showAIDifficultyPicker {
            return .alreadyBusy
        }

        let canPlay = entitlements.isPremium || lives.livesRemaining > 0
        guard canPlay else { return .outOfLives }

        matchmakingFellBackToAI = false
        pendingOnlineMatch = nil
        pendingAIMatch = false
        pendingAITier = nil

        if isLocalMode || session == nil {
            return .localAI
        }

        guard let userId = session?.userId else {
            return .localAI
        }

        startMatchmakingSearch(userId: userId, requestNotificationAuth: true)
        return .started
    }

    /// Stop searching and show the 1–10 difficulty picker.
    func presentAIDifficultyPicker() {
        matchmakingService.cancelSearch()
        isMatchmaking = false
        endMatchmakingBackgroundTask()
        matchmakingBanner = .hidden
        MatchmakingNotifications.clearMatchFound()
        selectedAIDifficulty = 5
        showAIDifficultyPicker = true
    }

    func dismissAIDifficultyPicker() {
        showAIDifficultyPicker = false
    }

    func confirmAIDifficultyAndPlay(tier: Int) {
        let clamped = min(10, max(1, tier))
        selectedAIDifficulty = clamped
        pendingAITier = clamped
        showAIDifficultyPicker = false
        matchmakingFellBackToAI = true
        pendingAIMatch = true

        if isInDailyPlay {
            startMatchAfterDailyExit = true
            requestExitDailyPlay = true
            return
        }
        startPendingAIMatch()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        isAppInForeground = phase == .active
        if phase == .active {
            MatchmakingNotifications.clearMatchFound()
            if !isInDailyPlay, let config = pendingOnlineMatch, matchmakingBanner == .hidden {
                matchmakingBanner = .matchFound(opponentName: config.opponentUsername)
            }
        } else if phase == .background, isMatchmaking {
            beginMatchmakingBackgroundTask()
        }
    }

    /// Player tapped the match-found banner.
    func acceptMatchmakingBannerAction() {
        guard pendingOnlineMatch != nil else { return }
        if isInDailyPlay {
            startMatchAfterDailyExit = true
            requestExitDailyPlay = true
            return
        }
        if let config = pendingOnlineMatch {
            startPendingOnlineMatch(config)
        }
    }

    private func startMatchmakingSearch(userId: String, requestNotificationAuth: Bool) {
        isMatchmaking = true
        matchmakingBanner = .searching
        beginMatchmakingBackgroundTask()

        Task {
            if requestNotificationAuth {
                await MatchmakingNotifications.requestAuthorizationIfNeeded()
            }
            guard self.isMatchmaking else { return }
            let result = await matchmakingService.searchForMatch(myUserId: userId)
            self.handleMatchmakingSearchResult(result)
        }
    }

    func handleDailyPlayDidDismiss() {
        isInDailyPlay = false
        requestExitDailyPlay = false
        guard startMatchAfterDailyExit else { return }
        startMatchAfterDailyExit = false
        if let config = pendingOnlineMatch {
            startPendingOnlineMatch(config)
        } else if pendingAIMatch {
            startPendingAIMatch()
        }
    }

    func dismissMatchmakingBanner() {
        if isMatchmaking {
            cancelQuickMatchSearch()
            return
        }
        startMatchAfterDailyExit = false
        pendingOnlineMatch = nil
        pendingAIMatch = false
        matchmakingBanner = .hidden
        MatchmakingNotifications.clearMatchFound()
    }

    private func handleMatchmakingSearchResult(_ result: QuickMatchSearchResult) {
        isMatchmaking = false
        endMatchmakingBackgroundTask()

        switch result {
        case .matched(let config):
            pendingOnlineMatch = config
            let busy = isInDailyPlay || !isAppInForeground
            if busy {
                matchmakingBanner = .matchFound(opponentName: config.opponentUsername)
                if !isAppInForeground {
                    MatchmakingNotifications.postMatchFound(opponentName: config.opponentUsername)
                }
            } else {
                startPendingOnlineMatch(config)
            }

        case .cancelled:
            // Don't clear if the player opened the AI difficulty picker.
            if !showAIDifficultyPicker {
                clearMatchmakingUI()
            }
        }
    }

    private func startPendingOnlineMatch(_ config: OnlineMatchConfig) {
        if !entitlements.isPremium {
            _ = lives.consumeLife()
            noteLifeDeductionIfNeeded()
        }
        pendingOnlineMatch = nil
        pendingAIMatch = false
        pendingAITier = nil
        matchmakingBanner = .hidden
        MatchmakingNotifications.clearMatchFound()
        onlineMatchToStart = config
    }

    private func startPendingAIMatch() {
        if !entitlements.isPremium {
            _ = lives.consumeLife()
            noteLifeDeductionIfNeeded()
        }
        pendingOnlineMatch = nil
        pendingAIMatch = false
        matchmakingBanner = .hidden
        MatchmakingNotifications.clearMatchFound()
        launchAIMatchToken += 1
    }

    private func clearMatchmakingUI() {
        pendingOnlineMatch = nil
        pendingAIMatch = false
        matchmakingBanner = .hidden
        MatchmakingNotifications.clearMatchFound()
    }

    private func beginMatchmakingBackgroundTask() {
        endMatchmakingBackgroundTask()
        matchmakingBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "worded.matchmaking") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // iOS is about to freeze us — we can't keep polling.
                if self.isMatchmaking, !self.isAppInForeground {
                    MatchmakingNotifications.postSearchPaused()
                }
                self.endMatchmakingBackgroundTask()
            }
        }
    }

    private func endMatchmakingBackgroundTask() {
        guard matchmakingBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(matchmakingBackgroundTask)
        matchmakingBackgroundTask = .invalid
    }

    /// Queues the contextual lives teach when a daily life was just spent.
    func noteLifeDeductionIfNeeded() {
        guard lives.didDeductLifeOnLastConsume else { return }
        onboardingStore.scheduleLivesIntro()
    }

    func cancelQuickMatchSearch() {
        matchmakingService.cancelSearch()
        isMatchmaking = false
        endMatchmakingBackgroundTask()
        clearMatchmakingUI()
    }

    func sendFriendChallenge(to username: String) async throws {
        guard !isLocalMode else { throw MatchChallengeError.notConfigured }
        _ = try await challengeService.sendChallenge(toUsername: username)
        isWaitingForChallengeAccept = true
        pendingInviteChallenge = challengeService.outgoingChallenge
        challengeStatusMessage = nil
    }

    func acceptIncomingChallenge() async {
        guard let invite = challengeService.incomingChallenge else { return }
        let canPlay = entitlements.isPremium
            || lives.livesRemaining > 0
            || lives.hasFreeFriendGame
        guard canPlay else {
            challengeStatusMessage = "You're out of lives — can't accept this challenge right now."
            return
        }
        do {
            let config = try await challengeService.acceptChallenge(invite)
            challengeService.markMatchStarted(config.matchId)
            onlineMatchToStart = config
            challengeService.clearAcceptedOutgoing()
            if !entitlements.isPremium {
                _ = lives.consumeLife(isFriendGame: true)
                noteLifeDeductionIfNeeded()
            }
        } catch {
            challengeStatusMessage = error.localizedDescription
        }
    }

    func rejectIncomingChallenge() async {
        guard let invite = challengeService.incomingChallenge else { return }
        try? await challengeService.rejectChallenge(invite)
    }

    func cancelOutgoingChallenge() async {
        await challengeService.cancelOutgoingChallenge()
        isWaitingForChallengeAccept = false
    }

    func handleOutgoingChallengeUpdate() {
        guard let invite = challengeService.outgoingChallenge,
              let session else { return }

        if invite.status == "accepted",
           let matchId = invite.matchId,
           !challengeService.hasStartedMatch(matchId),
           let config = challengeService.onlineConfig(for: invite, myUserId: session.userId) {
            isWaitingForChallengeAccept = false
            challengeService.markMatchStarted(matchId)
            onlineMatchToStart = config
            challengeService.clearAcceptedOutgoing()
        } else if invite.status == "rejected" {
            isWaitingForChallengeAccept = false
            challengeStatusMessage = "\(invite.opponentUsername) declined your challenge."
            challengeService.clearRejectedOutgoing()
        }
    }

    func finishOnlineMatch() {
        onlineMatchToStart = nil
        isWaitingForChallengeAccept = false
        pendingInviteChallenge = nil
    }

    /// Restores a saved Supabase session when opened within the last 7 days.
    /// Refreshes the access token and loads a cached profile so players aren't
    /// sent back through sign-in after every app launch.
    private func restoreOnlineSession() async {
        let client = SupabaseClient.shared

        guard client.isSessionWithinRetentionWindow(),
              let existing = client.currentSession else {
            client.signOut()
            session = nil
            profile = nil
            return
        }

        session = existing
        client.touchSessionActivity()

        if let cached = SupabaseClient.loadCachedProfile(forUserId: existing.userId) {
            profile = cached
            username = cached.username
            if let cachedCountry = cached.country, !cachedCountry.isEmpty {
                country = cachedCountry
            }
        } else if !username.isEmpty {
            // Pre-cache migration: username was saved before profile caching existed.
            let fallback = Profile(
                id: existing.userId, username: username, country: country,
                isPremium: entitlements.isPremium)
            profile = fallback
            SupabaseClient.cacheProfile(fallback)
        }

        do {
            session = try await client.refreshSession()
        } catch {
            // Still within the 7-day window — stay signed in with cached profile.
            if profile == nil {
                client.signOut()
                session = nil
            }
            return
        }

        await loadProfile()
    }

    func completeLocalSignIn(username: String, country: String) {
        guard WordDictionary.shared.isCleanUsername(username) else { return }
        self.username = username
        self.country = country
        UserDefaults.standard.set(username, forKey: "worded.username")
        UserDefaults.standard.set(country, forKey: "worded.country")
        session = Session(accessToken: "local", refreshToken: "local", userId: "local")
        profile = Profile(id: "local", username: username, country: country, isPremium: entitlements.isPremium)
    }

    func loadProfile() async {
        guard let session else { return }
        do {
            let data = try await SupabaseClient.shared.request(
                table: "profiles", query: "id=eq.\(session.userId)&select=*")
            let profiles = try JSONDecoder().decode([Profile].self, from: data)
            profile = profiles.first
            if let profile {
                username = profile.username
                UserDefaults.standard.set(profile.username, forKey: "worded.username")
                if let profileCountry = profile.country, !profileCountry.isEmpty {
                    country = profileCountry
                    UserDefaults.standard.set(profileCountry, forKey: "worded.country")
                }
                SupabaseClient.cacheProfile(profile)
            }
        } catch {
            // Profile row may not exist yet (fresh signup); AuthView handles creation.
        }
    }

    func createProfile(username: String, country: String) async throws {
        guard let session else { return }
        let payload: [String: Any] = [
            "id": session.userId,
            "username": username,
            "country": country,
            "is_premium": false,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await SupabaseClient.shared.request(
            table: "profiles", method: "POST", body: body, prefer: "return=representation")
        self.username = username
        self.country = country
        UserDefaults.standard.set(username, forKey: "worded.username")
        let newProfile = Profile(id: session.userId, username: username, country: country, isPremium: false)
        profile = newProfile
        SupabaseClient.cacheProfile(newProfile)
    }

    func signOut() {
        SupabaseClient.shared.signOut()
        session = nil
        profile = nil
    }

    /// Keeps the 7-day logged-in window open while the app is in use.
    func recordActivity() {
        guard session != nil, !isLocalMode else { return }
        SupabaseClient.shared.touchSessionActivity()
    }

    /// Signs out only after a full week without opening the app.
    func enforceSessionRetention() {
        guard !isLocalMode, session != nil else { return }
        if !SupabaseClient.shared.isSessionWithinRetentionWindow() {
            signOut()
        }
    }

    /// Copies saved data from the old Word-Off UserDefaults keys on first launch
    /// after the rebrand so testers don't lose username / promo premium.
    static func migrateLegacyDefaults() {
        let d = UserDefaults.standard
        let pairs: [(String, String)] = [
            ("wordoff.username", "worded.username"),
            ("wordoff.country", "worded.country"),
            ("wordoff.promo.premium", "worded.promo.premium"),
            ("wordoff.dailyPass.day", "worded.dailyPass.day"),
            ("wordoff.lives.day", "worded.lives.day"),
            ("wordoff.lives.used", "worded.lives.used"),
            ("wordoff.streak.count", "worded.streak.count"),
            ("wordoff.streak.lastLogin", "worded.streak.lastLogin"),
            ("wordoff.friendGameUsed", "worded.friendGameUsed"),
            ("wordoff.daily.unlocked", "worded.daily.unlocked"),
        ]
        for (oldKey, newKey) in pairs {
            if d.object(forKey: newKey) == nil, let value = d.object(forKey: oldKey) {
                d.set(value, forKey: newKey)
            }
        }
        if d.data(forKey: "worded.session") == nil,
           let sessionData = d.data(forKey: "wordoff.session") {
            d.set(sessionData, forKey: "worded.session")
        }
    }
}
