import Foundation
import SwiftUI
import Combine

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

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // Forward child object changes so views observing AppState refresh
        // when lives, purchases, daily results, or stats change.
        for child in [lives.objectWillChange.eraseToAnyPublisher(),
                      entitlements.objectWillChange.eraseToAnyPublisher(),
                      dailyStore.objectWillChange.eraseToAnyPublisher(),
                      statsStore.objectWillChange.eraseToAnyPublisher()] {
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
        await entitlements.refresh()

        if isLocalMode {
            // Local mode: a stored username acts as the "account".
            if !username.isEmpty {
                session = Session(accessToken: "local", refreshToken: "local", userId: "local")
                profile = Profile(id: "local", username: username, country: country, isPremium: entitlements.isPremium)
            }
        } else {
            await restoreOnlineSession()
        }
        isLoading = false
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
