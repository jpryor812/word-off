import Foundation

/// Minimal Supabase REST client (GoTrue auth + PostgREST) using URLSession.
/// Configure via SupabaseConfig. If unconfigured, the app runs in local mode:
/// daily puzzles and AI matches work; leaderboards and human PvP are disabled.
enum SupabaseConfig {
    private static let projectURL = "https://fiurnejfbipqfbqpjtow.supabase.co"
    private static let projectAnonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpdXJuZWpmYmlwcWZicXBqdG93Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMDgxODcsImV4cCI6MjA5ODY4NDE4N30.s4VREy7kfDcD_852kpPQy-zUjuQ2W9Px0xqoqqwn8MY"

    /// Scheme env vars override these when running from Xcode; hardcoded values
    /// are used for TestFlight and App Store builds.
    static let url = ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? projectURL
    static let anonKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? projectAnonKey

    static var isConfigured: Bool { !url.isEmpty && !anonKey.isEmpty }
}

struct Session: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var userId: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case userId = "user_id"
    }
}

/// Cached profile JSON so returning players skip the username screen when offline
/// or while the access token is being refreshed.
private let profileCacheKey = "worded.profile.cache"
private let lastActiveKey = "worded.session.lastActiveAt"
private let sessionRetention: TimeInterval = 7 * 24 * 60 * 60

struct Profile: Codable, Equatable {
    var id: String
    var username: String
    var country: String?
    var isPremium: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, country
        case isPremium = "is_premium"
    }
}

enum SupabaseError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Online features need a Supabase project. Playing in local mode."
        case .http(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decoding:
            return "Unexpected server response."
        }
    }
}

final class SupabaseClient {
    static let shared = SupabaseClient()
    private let session = URLSession.shared

    var currentSession: Session? {
        didSet { persistSession() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "worded.session"),
           let saved = try? JSONDecoder().decode(Session.self, from: data) {
            currentSession = saved
            // Existing installs: treat as recently active so we don't boot them out.
            if UserDefaults.standard.object(forKey: lastActiveKey) == nil {
                touchSessionActivity()
            }
        }
    }

    /// Records app use so the 7-day stay-logged-in window stays open.
    func touchSessionActivity() {
        UserDefaults.standard.set(Date(), forKey: lastActiveKey)
    }

    /// True when the player opened the app within the last 7 days.
    func isSessionWithinRetentionWindow() -> Bool {
        guard currentSession != nil else { return false }
        guard let last = UserDefaults.standard.object(forKey: lastActiveKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(last) <= sessionRetention
    }

    static func loadCachedProfile(forUserId userId: String) -> Profile? {
        guard let data = UserDefaults.standard.data(forKey: profileCacheKey),
              let profile = try? JSONDecoder().decode(Profile.self, from: data),
              profile.id == userId else {
            return nil
        }
        return profile
    }

    static func cacheProfile(_ profile: Profile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileCacheKey)
        }
    }

    static func clearCachedProfile() {
        UserDefaults.standard.removeObject(forKey: profileCacheKey)
    }

    private func persistSession() {
        if let session = currentSession, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: "worded.session")
            touchSessionActivity()
        } else {
            UserDefaults.standard.removeObject(forKey: "worded.session")
            UserDefaults.standard.removeObject(forKey: lastActiveKey)
            Self.clearCachedProfile()
        }
    }

    /// Swaps a stale access token for a fresh one using the saved refresh token.
    @discardableResult
    func refreshSession() async throws -> Session {
        guard let existing = currentSession else { throw SupabaseError.notConfigured }
        let json = try await authRequest(
            path: "token?grant_type=refresh_token",
            body: ["refresh_token": existing.refreshToken])
        return try parseSession(json)
    }

    // MARK: - Auth

    func signUp(email: String, password: String) async throws -> Session {
        let body = ["email": email, "password": password]
        let json = try await authRequest(path: "signup", body: body)
        return try parseSession(json)
    }

    func signIn(email: String, password: String) async throws -> Session {
        let body = ["email": email, "password": password]
        let json = try await authRequest(path: "token?grant_type=password", body: body)
        return try parseSession(json)
    }

    /// Exchanges a Sign in with Apple identity token for a Supabase session.
    func signInWithApple(idToken: String) async throws -> Session {
        let body = ["provider": "apple", "id_token": idToken]
        let json = try await authRequest(path: "token?grant_type=id_token", body: body)
        return try parseSession(json)
    }

    func signOut() {
        currentSession = nil
    }

    private func parseSession(_ json: [String: Any]) throws -> Session {
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let userId = user["id"] as? String else {
            throw SupabaseError.decoding
        }
        let newSession = Session(accessToken: access, refreshToken: refresh, userId: userId)
        currentSession = newSession
        return newSession
    }

    private func authRequest(path: String, body: [String: String]) async throws -> [String: Any] {
        guard SupabaseConfig.isConfigured else { throw SupabaseError.notConfigured }
        var request = URLRequest(url: URL(string: "\(SupabaseConfig.url)/auth/v1/\(path)")!)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?["msg"] as? String ?? $0?["error_description"] as? String } ?? "unknown"
            throw SupabaseError.http(code, message)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupabaseError.decoding
        }
        return json
    }

    // MARK: - PostgREST

    func request(
        table: String,
        method: String = "GET",
        query: String = "",
        body: Data? = nil,
        prefer: String? = nil
    ) async throws -> Data {
        let (data, code) = try await performRequest(
            table: table, method: method, query: query, body: body, prefer: prefer)

        // Access tokens expire ~hourly; refresh once and retry so background
        // polling (challenge invites, submissions) doesn't silently die.
        if code == 401, currentSession != nil {
            try await refreshSessionDeduped()
            let (retryData, retryCode) = try await performRequest(
                table: table, method: method, query: query, body: body, prefer: prefer)
            guard (200..<300).contains(retryCode) else {
                throw SupabaseError.http(retryCode, String(data: retryData, encoding: .utf8) ?? "")
            }
            return retryData
        }

        guard (200..<300).contains(code) else {
            throw SupabaseError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func performRequest(
        table: String,
        method: String,
        query: String,
        body: Data?,
        prefer: String?
    ) async throws -> (Data, Int) {
        guard SupabaseConfig.isConfigured else { throw SupabaseError.notConfigured }
        let urlString = "\(SupabaseConfig.url)/rest/v1/\(table)\(query.isEmpty ? "" : "?\(query)")"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = currentSession?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, code)
    }

    /// Serializes concurrent 401 retries into a single token refresh.
    private var refreshTask: Task<Session, Error>?

    private func refreshSessionDeduped() async throws {
        if let existing = refreshTask {
            _ = try await existing.value
            return
        }
        let task = Task { [self] in
            defer { refreshTask = nil }
            return try await refreshSession()
        }
        refreshTask = task
        _ = try await task.value
    }
}
