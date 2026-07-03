import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isLoading = true
    @Published var session: Session?
    @Published var profile: Profile?
    @Published var username: String = UserDefaults.standard.string(forKey: "wordoff.username") ?? ""
    @Published var country: String = UserDefaults.standard.string(forKey: "wordoff.country") ?? ""

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
        } else if let existing = SupabaseClient.shared.currentSession {
            session = existing
            await loadProfile()
        }
        isLoading = false
    }

    func completeLocalSignIn(username: String, country: String) {
        guard WordDictionary.shared.isCleanUsername(username) else { return }
        self.username = username
        self.country = country
        UserDefaults.standard.set(username, forKey: "wordoff.username")
        UserDefaults.standard.set(country, forKey: "wordoff.country")
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
                UserDefaults.standard.set(profile.username, forKey: "wordoff.username")
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
        UserDefaults.standard.set(username, forKey: "wordoff.username")
        profile = Profile(id: session.userId, username: username, country: country, isPremium: false)
    }

    func signOut() {
        SupabaseClient.shared.signOut()
        session = nil
        profile = nil
    }
}
