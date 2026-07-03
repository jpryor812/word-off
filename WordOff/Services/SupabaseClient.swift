import Foundation

/// Minimal Supabase REST client (GoTrue auth + PostgREST) using URLSession.
/// Configure via SupabaseConfig. If unconfigured, the app runs in local mode:
/// daily puzzles and AI matches work; leaderboards and human PvP are disabled.
enum SupabaseConfig {
    // TODO: paste your project values here (Settings -> API in Supabase dashboard).
    static let url = ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? ""
    static let anonKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? ""

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
        if let data = UserDefaults.standard.data(forKey: "wordoff.session"),
           let saved = try? JSONDecoder().decode(Session.self, from: data) {
            currentSession = saved
        }
    }

    private func persistSession() {
        if let session = currentSession, let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: "wordoff.session")
        } else {
            UserDefaults.standard.removeObject(forKey: "wordoff.session")
        }
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
        guard (200..<300).contains(code) else {
            throw SupabaseError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
