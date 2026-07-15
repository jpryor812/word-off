import Foundation

enum MatchmakingError: LocalizedError {
    case notConfigured
    case notSignedIn
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Online matchmaking requires an internet connection."
        case .notSignedIn:
            return "Sign in to play online against other players."
        case .decoding:
            return "Unexpected matchmaking response."
        }
    }
}

enum QuickMatchSearchResult: Equatable {
    case matched(OnlineMatchConfig)
    case aiFallback
    case cancelled
}

/// Searches the Supabase matchmaking queue for a human opponent, polling until
/// paired or the timeout elapses (then the caller falls back to AI).
@MainActor
final class MatchmakingService: ObservableObject {
    @Published private(set) var isSearching = false

    private var searchTask: Task<QuickMatchSearchResult, Never>?

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        Task { try? await cancelQueueEntry() }
    }

    func searchForMatch(
        myUserId: String,
        timeoutSeconds: Int = GameConstants.matchmakingTimeoutSeconds
    ) async -> QuickMatchSearchResult {
        searchTask?.cancel()
        let task = Task { () -> QuickMatchSearchResult in
            await performSearch(myUserId: myUserId, timeoutSeconds: timeoutSeconds)
        }
        searchTask = task
        isSearching = true
        let result = await task.value
        isSearching = false
        searchTask = nil
        return result
    }

    private func performSearch(myUserId: String, timeoutSeconds: Int) async -> QuickMatchSearchResult {
        guard SupabaseConfig.isConfigured else { return .aiFallback }
        guard SupabaseClient.shared.currentSession != nil else { return .aiFallback }

        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

        while !Task.isCancelled {
            do {
                if let config = try await enqueueOrPoll(myUserId: myUserId) {
                    return .matched(config)
                }
            } catch {
                if Task.isCancelled { return .cancelled }
            }

            if Date() >= deadline {
                try? await cancelQueueEntry()
                return .aiFallback
            }

            try? await Task.sleep(for: .seconds(1))
        }

        try? await cancelQueueEntry()
        return .cancelled
    }

    private func enqueueOrPoll(myUserId: String) async throws -> OnlineMatchConfig? {
        let data = try await SupabaseClient.shared.rpc("enqueue_matchmaking")
        return try await parseMatchmakingResponse(data, myUserId: myUserId)
    }

    private func parseMatchmakingResponse(_ data: Data, myUserId: String) async throws -> OnlineMatchConfig? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            throw MatchmakingError.decoding
        }

        switch status {
        case "waiting", "idle":
            return nil
        case "matched":
            guard let matchId = json["match_id"] as? String,
                  let seed = json["seed"] as? String,
                  let opponentId = json["opponent_id"] as? String else {
                throw MatchmakingError.decoding
            }
            let username = await fetchUsername(for: opponentId) ?? "Player"
            let isPlayerA = json["is_player_a"] as? Bool ?? false
            return OnlineMatchConfig(
                matchId: matchId,
                seed: seed,
                opponentUserId: opponentId,
                opponentUsername: username,
                isChallenger: isPlayerA)
        default:
            return nil
        }
    }

    private func cancelQueueEntry() async throws {
        _ = try await SupabaseClient.shared.rpc("cancel_matchmaking")
    }

    private func fetchUsername(for userId: String) async -> String? {
        guard let data = try? await SupabaseClient.shared.request(
            table: "profiles", query: "id=eq.\(userId)&select=username"),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else { return nil }
        return row["username"] as? String
    }
}
