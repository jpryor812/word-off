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
    /// Quick Match needs a signed-in online account (AI is a separate button).
    case needsSignIn
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
    let friendsService = FriendsService()
    let onboardingStore = OnboardingStore()
    let settings = SettingsStore.shared

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
    /// First-time online rules card (before search starts).
    @Published var showOnlineRulesIntro = false
    /// Explain-then-ask for notifications after first Play Online search starts.
    @Published var showMatchmakingNotifyIntro = false
    /// Start search after the online-rules card is dismissed.
    private var pendingQuickMatchAfterRules = false
    /// Daily puzzle is on screen — don't auto-interrupt with a found match.
    @Published var isInDailyPlay = false
    /// Ask DailyPlayView to dismiss so a pending match can start.
    @Published var requestExitDailyPlay = false
    private var startMatchAfterDailyExit = false
    private var isAppInForeground = true
    private var matchmakingBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var someoneWaitingPollTask: Task<Void, Never>?
    /// Avoid re-firing local notifications for the same social event.
    private var notifiedChallengeIds: Set<String> = []
    private var notifiedFriendRequestIds: Set<String> = []

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
                      friendsService.objectWillChange.eraseToAnyPublisher(),
                      onboardingStore.objectWillChange.eraseToAnyPublisher(),
                      settings.objectWillChange.eraseToAnyPublisher()] {
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
            if session != nil {
                friendsService.start()
            }
        }
        isLoading = false
        await processPendingDeepLinkIfNeeded()
        await refreshDailyReminderNotification()
        if !isLocalMode, session != nil {
            await PushRegistration.syncStoredTokenIfNeeded()
        }
    }

    private func openChallengeFromDeepLink(_ challengeId: String) async {
        guard !isLocalMode else { return }
        do {
            _ = try await challengeService.fetchChallengeForDeepLink(id: challengeId)
        } catch {
            challengeStatusMessage = error.localizedDescription
        }
    }

    func openChallengeFromNotification(challengeId: String) async {
        await openChallengeFromDeepLink(challengeId)
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

    /// Starts a non-blocking human quick-match search (banner stays up while browsing).
    /// Life is consumed only when a human match actually begins. Never falls back to AI.
    func beginBackgroundQuickMatch() -> BeginQuickMatchResult {
        if isMatchmaking || pendingOnlineMatch != nil || pendingAIMatch || showAIDifficultyPicker
            || showOnlineRulesIntro || showMatchmakingNotifyIntro {
            return .alreadyBusy
        }

        let canPlay = entitlements.isPremium || lives.livesRemaining > 0
        guard canPlay else { return .outOfLives }

        matchmakingFellBackToAI = false
        pendingOnlineMatch = nil
        pendingAIMatch = false
        pendingAITier = nil

        if isLocalMode || session == nil {
            return .needsSignIn
        }

        guard session?.userId != nil else {
            return .needsSignIn
        }

        // First online game: teach rules before enqueueing a search.
        if !settings.didExplainOnlineRules {
            pendingQuickMatchAfterRules = true
            showOnlineRulesIntro = true
            return .started
        }

        beginQuickMatchSearchAfterIntros()
        return .started
    }

    /// After the online-rules card — start searching, then show the notify intro if needed.
    func completeOnlineRulesIntro() {
        showOnlineRulesIntro = false
        settings.didExplainOnlineRules = true
        guard pendingQuickMatchAfterRules else { return }
        pendingQuickMatchAfterRules = false
        beginQuickMatchSearchAfterIntros()
    }

    private func beginQuickMatchSearchAfterIntros() {
        guard let userId = session?.userId else { return }
        startMatchmakingSearch(userId: userId, requestNotificationAuth: false)
        if !settings.didPromptMatchmakingNotify {
            showMatchmakingNotifyIntro = true
        }
    }

    /// Explicit Play AI — difficulty picker. Cancels any human search first.
    func presentAIDifficultyPicker() {
        let canPlay = entitlements.isPremium || lives.livesRemaining > 0
        guard canPlay else {
            // Home shows the out-of-lives alert via beginAIMatch().
            return
        }
        matchmakingService.cancelSearch()
        isMatchmaking = false
        endMatchmakingBackgroundTask()
        matchmakingBanner = .hidden
        MatchmakingNotifications.clearMatchFound()
        selectedAIDifficulty = 5
        showAIDifficultyPicker = true
    }

    /// Starts the AI difficulty flow from Home. Returns false if out of lives.
    func beginAIMatch() -> Bool {
        let canPlay = entitlements.isPremium || lives.livesRemaining > 0
        guard canPlay else { return false }
        presentAIDifficultyPicker()
        return true
    }

    func dismissAIDifficultyPicker() {
        showAIDifficultyPicker = false
    }

    func confirmAIDifficultyAndPlay(tier: Int) {
        let clamped = min(10, max(1, tier))
        selectedAIDifficulty = clamped
        pendingAITier = clamped
        showAIDifficultyPicker = false
        matchmakingFellBackToAI = false
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
            Task { await refreshDailyReminderNotification() }
            startSomeoneWaitingPolling()
            if !isLocalMode, session != nil {
                friendsService.startHeartbeat()
                friendsService.start()
            }
        } else {
            stopSomeoneWaitingPolling()
            friendsService.stopHeartbeat()
            if phase == .background {
                Task {
                    await checkSomeoneWaitingAndNotify()
                    await notifySocialEventsIfNeeded()
                    friendsService.stop()
                }
                if isMatchmaking {
                    beginMatchmakingBackgroundTask()
                }
            }
        }
    }

    /// Local notifications for pending challenges / friend requests when leaving the app.
    private func notifySocialEventsIfNeeded() async {
        guard !isLocalMode, session != nil else { return }
        await challengeService.refresh()
        await friendsService.refresh()

        if let invite = challengeService.incomingChallenge,
           !notifiedChallengeIds.contains(invite.id) {
            notifiedChallengeIds.insert(invite.id)
            SocialNotifications.postChallenge(from: invite.challengerUsername)
        }
        for request in friendsService.incomingRequests where !notifiedFriendRequestIds.contains(request.id) {
            notifiedFriendRequestIds.insert(request.id)
            SocialNotifications.postFriendRequest(from: request.otherUsername)
        }
    }

    /// Schedule (or clear) the 8pm local daily reminder based on today's progress.
    func refreshDailyReminderNotification() async {
        let today = DailySeed.todayString()
        let hasPlayed = dailyStore.completedCount(day: today) > 0
        await DailyReminderNotifications.refresh(hasPlayedAnyDailyToday: hasPlayed)
    }

    /// Restart queue peeking after the Settings toggle changes.
    func refreshSomeoneWaitingPolling() {
        if isAppInForeground {
            startSomeoneWaitingPolling()
        } else {
            stopSomeoneWaitingPolling()
        }
    }

    private func startSomeoneWaitingPolling() {
        stopSomeoneWaitingPolling()
        guard !isLocalMode, session != nil else { return }
        guard settings.notificationsEnabled, settings.notifyWhenSomeoneWaiting else { return }
        someoneWaitingPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkSomeoneWaitingAndNotify()
                try? await Task.sleep(for: .seconds(45))
            }
        }
    }

    private func stopSomeoneWaitingPolling() {
        someoneWaitingPollTask?.cancel()
        someoneWaitingPollTask = nil
    }

    private func checkSomeoneWaitingAndNotify() async {
        guard settings.canSendSomeoneWaitingPing() else { return }
        guard !isMatchmaking, onlineMatchToStart == nil else { return }
        let waiting = await matchmakingService.isSomeoneWaiting()
        guard waiting else { return }
        MatchmakingNotifications.postSomeoneWaiting()
        settings.markSomeoneWaitingPingSent()
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

    /// After the “search can take a minute” card — show the system notification prompt.
    func completeMatchmakingNotifyIntro() async {
        showMatchmakingNotifyIntro = false
        settings.didPromptMatchmakingNotify = true
        await MatchmakingNotifications.requestAuthorizationIfNeeded()
        await refreshDailyReminderNotification()
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
            // Only auto-launch if we sent a challenge this session and are waiting.
            // Otherwise a stale accept (e.g. after reinstall / re-login) would yank
            // the player into an old match — often against someone who isn't online,
            // which feels like a broken AI game.
            guard isWaitingForChallengeAccept else {
                challengeService.markMatchStarted(matchId)
                challengeService.clearAcceptedOutgoing()
                return
            }
            isWaitingForChallengeAccept = false
            challengeService.markMatchStarted(matchId)
            onlineMatchToStart = config
            challengeService.clearAcceptedOutgoing()
        } else if invite.status == "rejected" {
            isWaitingForChallengeAccept = false
            challengeStatusMessage = "\(invite.opponentUsername) declined your challenge."
            challengeService.clearRejectedOutgoing()
        } else if invite.status == "expired" || invite.isExpired {
            isWaitingForChallengeAccept = false
            challengeStatusMessage = "Your challenge to \(invite.opponentUsername) expired after 6 hours."
            challengeService.clearExpiredOutgoing()
        }
    }

    func finishOnlineMatch() {
        onlineMatchToStart = nil
        isWaitingForChallengeAccept = false
        pendingInviteChallenge = nil
        onboardingStore.beginSomeoneWaitingSettingsAfterOnlineMatch()
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
                startSocialServicesIfNeeded()
            }
        } catch {
            // Profile row may not exist yet (fresh signup); AuthView handles creation.
        }
    }

    private func startSocialServicesIfNeeded() {
        guard !isLocalMode, session != nil else { return }
        challengeService.startPolling()
        friendsService.start()
        Task { await PushRegistration.syncStoredTokenIfNeeded() }
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
        startSocialServicesIfNeeded()
    }

    func signOut() {
        friendsService.stop()
        challengeService.stopPolling()
        Task { @MainActor in
            await PushRegistration.clearTokenFromServer()
            SupabaseClient.shared.signOut()
            session = nil
            profile = nil
        }
    }

    /// Permanently deletes the signed-in account and clears local data (App Store 5.1.1(v)).
    func deleteAccount() async throws {
        if !isLocalMode, session != nil {
            _ = try await SupabaseClient.shared.rpc("delete_own_account")
        }
        clearLocalAccountData()
        signOut()
    }

    private func clearLocalAccountData() {
        let defaults = UserDefaults.standard
        let keys = [
            "worded.username", "worded.country", "worded.session", "worded.profile.cache",
            "worded.session.lastActiveAt", "worded.onboarding.completedVersion",
            "worded.onboarding.livesIntroCompleted", "worded.onboarding.welcomeIntroCompleted",
            "worded.lives.day", "worded.lives.used", "worded.streak.count", "worded.streak.lastLogin",
            "worded.friendGameUsed", "worded.daily.unlocked", "worded.daily.streak.count",
            "worded.daily.streak.lastDay", "worded.dailyPass.day", "worded.promo.premium",
            "worded.promo.expiresAt", "worded.challenge.startedMatchIds",
        ]
        for key in keys { defaults.removeObject(forKey: key) }
        username = ""
        country = ""
        dailyStore.clearAllResults()
        statsStore.clearAll()
        badgeStore.clearAll()
        settings.notifyWhenSomeoneWaiting = false
        onboardingStore.resetForAccountDeletion()
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
