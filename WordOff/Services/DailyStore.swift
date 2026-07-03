import Foundation

/// Persists daily puzzle results locally (offline-first) and syncs scores to
/// Supabase leaderboards when a backend is configured.
@MainActor
final class DailyStore: ObservableObject {
    @Published private(set) var results: [DailyPuzzleResult] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("daily_results.json")
    }()

    init() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DailyPuzzleResult].self, from: data) else { return }
        results = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(results) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func result(day: String, rackSize: Int) -> DailyPuzzleResult? {
        results.first { $0.date == day && $0.rackSize == rackSize }
    }

    func hasPlayed(day: String, rackSize: Int) -> Bool {
        result(day: day, rackSize: rackSize) != nil
    }

    func save(_ result: DailyPuzzleResult) {
        results.removeAll { $0.id == result.id }
        results.append(result)
        persist()
        Task { await sync(result) }
    }

    /// Uploads the score for leaderboard ranking. Fails silently offline; the
    /// local result is the source of truth for the player's own history.
    private func sync(_ result: DailyPuzzleResult) async {
        guard SupabaseConfig.isConfigured,
              let session = SupabaseClient.shared.currentSession else { return }
        let payload: [String: Any] = [
            "user_id": session.userId,
            "day": result.date,
            "rack_size": result.rackSize,
            "score": result.totalScore,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        _ = try? await SupabaseClient.shared.request(
            table: "daily_scores", method: "POST", body: body,
            prefer: "resolution=merge-duplicates")
    }

    /// Fetches rank + percentile for a submitted daily score.
    func fetchStanding(day: String, rackSize: Int, score: Int) async -> (rank: Int, total: Int)? {
        guard SupabaseConfig.isConfigured else { return nil }
        do {
            let better = try await count(query: "day=eq.\(day)&rack_size=eq.\(rackSize)&score=gt.\(score)")
            let total = try await count(query: "day=eq.\(day)&rack_size=eq.\(rackSize)")
            return (better + 1, max(total, 1))
        } catch {
            return nil
        }
    }

    private func count(query: String) async throws -> Int {
        var request = URLRequest(url: URL(string: "\(SupabaseConfig.url)/rest/v1/daily_scores?\(query)&select=user_id")!)
        request.httpMethod = "HEAD"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = SupabaseClient.shared.currentSession?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("count=exact", forHTTPHeaderField: "Prefer")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              let range = http.value(forHTTPHeaderField: "Content-Range"),
              let totalString = range.split(separator: "/").last,
              let total = Int(totalString) else {
            throw SupabaseError.decoding
        }
        return total
    }
}
