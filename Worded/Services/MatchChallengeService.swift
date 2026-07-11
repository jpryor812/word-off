import Foundation

enum MatchChallengeError: LocalizedError {
    case notConfigured
    case notSignedIn
    case userNotFound
    case cannotChallengeSelf
    case alreadyPending
    case notFound

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Online play requires an internet connection and account."
        case .notSignedIn:
            return "Sign in to challenge friends online."
        case .userNotFound:
            return "No player found with that username."
        case .cannotChallengeSelf:
            return "You can't challenge yourself!"
        case .alreadyPending:
            return "A challenge is already waiting with this player."
        case .notFound:
            return "That challenge is no longer available."
        }
    }
}

/// Sends friend challenges, polls for responses, and syncs human match submissions.
@MainActor
final class MatchChallengeService: ObservableObject {
    @Published private(set) var incomingChallenge: MatchChallengeInvite?
    @Published private(set) var outgoingChallenge: MatchChallengeInvite?

    private var pollTask: Task<Void, Never>?
    private static let startedMatchIdsKey = "worded.challenge.startedMatchIds"

    /// Match IDs we've already launched — prevents re-opening stale accepted challenges.
    private var startedMatchIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.startedMatchIdsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.startedMatchIdsKey) }
    }

    func hasStartedMatch(_ matchId: String) -> Bool {
        startedMatchIds.contains(matchId)
    }

    func markMatchStarted(_ matchId: String) {
        var ids = startedMatchIds
        ids.insert(matchId)
        startedMatchIds = ids
        if outgoingChallenge?.matchId == matchId {
            outgoingChallenge = nil
        }
    }

    func startPolling() {
        guard SupabaseConfig.isConfigured, SupabaseClient.shared.currentSession != nil else { return }
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard let session = SupabaseClient.shared.currentSession else { return }
        await refreshIncoming(for: session.userId)
        await refreshOutgoing(for: session.userId)
    }

    // MARK: - Send / respond

    func sendChallenge(toUsername username: String) async throws -> MatchChallengeInvite {
        guard SupabaseConfig.isConfigured else { throw MatchChallengeError.notConfigured }
        guard let session = SupabaseClient.shared.currentSession else { throw MatchChallengeError.notSignedIn }

        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WordDictionary.shared.isCleanUsername(trimmed) else { throw MatchChallengeError.userNotFound }

        guard let opponent = try await fetchProfile(username: trimmed) else {
            throw MatchChallengeError.userNotFound
        }
        guard opponent.id != session.userId else { throw MatchChallengeError.cannotChallengeSelf }

        // If they already challenged us, don't stack a reverse challenge on top.
        if try await hasPending(challengerId: opponent.id, opponentId: session.userId) {
            throw MatchChallengeError.alreadyPending
        }

        // Cancel any of our own stale pending challenges to this player so
        // re-sending always works (old ones otherwise block forever).
        await cancelPending(challengerId: session.userId, opponentId: opponent.id)

        let seed = UUID().uuidString
        let payload: [String: Any] = [
            "challenger_id": session.userId,
            "opponent_id": opponent.id,
            "seed": seed,
            "status": "pending",
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await SupabaseClient.shared.request(
            table: "match_challenges",
            method: "POST",
            body: body,
            prefer: "return=representation")
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first,
              let invite = parseChallenge(row, challengerUsername: nil, opponentUsername: opponent.username) else {
            throw SupabaseError.decoding
        }
        if let full = try await fetchChallenge(id: invite.id) {
            outgoingChallenge = full
            return full
        }
        outgoingChallenge = invite
        return invite
    }

    func acceptChallenge(_ challenge: MatchChallengeInvite) async throws -> OnlineMatchConfig {
        guard let session = SupabaseClient.shared.currentSession else { throw MatchChallengeError.notSignedIn }
        guard challenge.status == "pending", challenge.opponentId == session.userId else {
            throw MatchChallengeError.notFound
        }

        let matchPayload: [String: Any] = [
            "player_a": challenge.challengerId,
            "player_b": challenge.opponentId,
            "seed": challenge.seed,
            "state": "active",
        ]
        let matchBody = try JSONSerialization.data(withJSONObject: matchPayload)
        let matchData = try await SupabaseClient.shared.request(
            table: "matches",
            method: "POST",
            body: matchBody,
            prefer: "return=representation")
        guard let matchRows = try JSONSerialization.jsonObject(with: matchData) as? [[String: Any]],
              let matchRow = matchRows.first,
              let matchId = matchRow["id"] as? String else {
            throw SupabaseError.decoding
        }

        let updateBody = try JSONSerialization.data(withJSONObject: [
            "status": "accepted",
            "match_id": matchId,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ])
        _ = try await SupabaseClient.shared.request(
            table: "match_challenges",
            method: "PATCH",
            query: "id=eq.\(challenge.id)",
            body: updateBody)

        incomingChallenge = nil
        return OnlineMatchConfig(
            matchId: matchId,
            seed: challenge.seed,
            opponentUserId: challenge.challengerId,
            opponentUsername: challenge.challengerUsername,
            isChallenger: false)
    }

    func rejectChallenge(_ challenge: MatchChallengeInvite) async throws {
        guard let session = SupabaseClient.shared.currentSession else { throw MatchChallengeError.notSignedIn }
        guard challenge.opponentId == session.userId else { throw MatchChallengeError.notFound }

        let body = try JSONSerialization.data(withJSONObject: [
            "status": "rejected",
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ])
        _ = try await SupabaseClient.shared.request(
            table: "match_challenges",
            method: "PATCH",
            query: "id=eq.\(challenge.id)",
            body: body)
        incomingChallenge = nil
    }

    func cancelOutgoingChallenge() async {
        guard let challenge = outgoingChallenge else { return }
        if let body = try? JSONSerialization.data(withJSONObject: [
            "status": "cancelled",
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]) {
            _ = try? await SupabaseClient.shared.request(
                table: "match_challenges",
                method: "PATCH",
                query: "id=eq.\(challenge.id)",
                body: body)
        }
        outgoingChallenge = nil
    }

    func clearRejectedOutgoing() {
        if outgoingChallenge?.status == "rejected" {
            outgoingChallenge = nil
        }
    }

    func clearAcceptedOutgoing() {
        if outgoingChallenge?.status == "accepted" {
            outgoingChallenge = nil
        }
    }

    func onlineConfig(for challenge: MatchChallengeInvite, myUserId: String) -> OnlineMatchConfig? {
        guard challenge.status == "accepted", let matchId = challenge.matchId else { return nil }
        let isChallenger = challenge.challengerId == myUserId
        return OnlineMatchConfig(
            matchId: matchId,
            seed: challenge.seed,
            opponentUserId: isChallenger ? challenge.opponentId : challenge.challengerId,
            opponentUsername: isChallenger ? challenge.opponentUsername : challenge.challengerUsername,
            isChallenger: isChallenger)
    }

    func fetchChallengeForDeepLink(id: String) async throws -> MatchChallengeInvite? {
        guard let session = SupabaseClient.shared.currentSession else {
            throw MatchChallengeError.notSignedIn
        }
        guard let invite = try await fetchChallenge(id: id) else {
            throw MatchChallengeError.notFound
        }
        guard invite.opponentId == session.userId, invite.status == "pending" else {
            throw MatchChallengeError.notFound
        }
        incomingChallenge = invite
        return invite
    }

    // MARK: - Submissions

    func submitWord(matchId: String, roundKey: Int, word: String, submittedMs: Int) async {
        guard let session = SupabaseClient.shared.currentSession else { return }
        guard let body = try? JSONSerialization.data(withJSONObject: [
            "match_id": matchId,
            "round": roundKey,
            "user_id": session.userId,
            "word": word,
            "submitted_ms": submittedMs,
        ]) else { return }
        _ = try? await SupabaseClient.shared.request(
            table: "match_submissions",
            method: "POST",
            body: body,
            prefer: "resolution=merge-duplicates")
    }

    func fetchOpponentSubmission(
        matchId: String,
        roundKey: Int,
        opponentUserId: String
    ) async -> (word: String?, submittedAt: TimeInterval?) {
        do {
            let query = "match_id=eq.\(matchId)&round=eq.\(roundKey)&user_id=eq.\(opponentUserId)&select=word,submitted_ms"
            let data = try await SupabaseClient.shared.request(table: "match_submissions", query: query)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = rows.first else { return (nil, nil) }
            let word = row["word"] as? String
            let ms = row["submitted_ms"] as? Int
            return (word, ms.map { TimeInterval($0) / 1000.0 })
        } catch {
            return (nil, nil)
        }
    }

    // MARK: - Private helpers

    private struct ProfileLookup: Decodable {
        let id: String
        let username: String
    }

    private func fetchProfile(username: String) async throws -> ProfileLookup? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let data = try await SupabaseClient.shared.request(
            table: "profiles",
            query: "username=eq.\(encoded)&select=id,username")
        return try JSONDecoder().decode([ProfileLookup].self, from: data).first
    }

    private func hasPending(challengerId: String, opponentId: String) async throws -> Bool {
        let q = "status=eq.pending&challenger_id=eq.\(challengerId)&opponent_id=eq.\(opponentId)&select=id"
        let data = try await SupabaseClient.shared.request(table: "match_challenges", query: q)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return false }
        return !rows.isEmpty
    }

    private func cancelPending(challengerId: String, opponentId: String) async {
        guard let body = try? JSONSerialization.data(withJSONObject: [
            "status": "cancelled",
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]) else { return }
        _ = try? await SupabaseClient.shared.request(
            table: "match_challenges",
            method: "PATCH",
            query: "challenger_id=eq.\(challengerId)&opponent_id=eq.\(opponentId)&status=eq.pending",
            body: body)
    }

    private func fetchChallenge(id: String) async throws -> MatchChallengeInvite? {
        let data = try await SupabaseClient.shared.request(
            table: "match_challenges",
            query: "id=eq.\(id)&select=*")
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else { return nil }
        return await enrichWithUsernames(parseChallenge(row, challengerUsername: nil, opponentUsername: nil))
    }

    private func enrichWithUsernames(_ invite: MatchChallengeInvite?) async -> MatchChallengeInvite? {
        guard let invite else { return nil }
        async let cName = username(for: invite.challengerId)
        async let oName = username(for: invite.opponentId)
        let (challengerUsername, opponentUsername) = await (cName, oName)
        return MatchChallengeInvite(
            id: invite.id,
            challengerId: invite.challengerId,
            opponentId: invite.opponentId,
            challengerUsername: challengerUsername ?? invite.challengerUsername,
            opponentUsername: opponentUsername ?? invite.opponentUsername,
            status: invite.status,
            seed: invite.seed,
            matchId: invite.matchId)
    }

    private func username(for userId: String) async -> String? {
        guard let data = try? await SupabaseClient.shared.request(
            table: "profiles", query: "id=eq.\(userId)&select=username"),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else { return nil }
        return row["username"] as? String
    }

    private func refreshIncoming(for userId: String) async {
        do {
            let data = try await SupabaseClient.shared.request(
                table: "match_challenges",
                query: "opponent_id=eq.\(userId)&status=eq.pending&order=created_at.desc&limit=1&select=*")
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = rows.first else {
                if incomingChallenge?.status == "pending" { incomingChallenge = nil }
                return
            }
            incomingChallenge = await enrichWithUsernames(parseChallenge(row, challengerUsername: nil, opponentUsername: nil))
        } catch {}
    }

    private func refreshOutgoing(for userId: String) async {
        do {
            if let pending = try await fetchLatestChallenge(
                challengerId: userId, status: "pending") {
                outgoingChallenge = pending
                return
            }

            if let accepted = try await fetchLatestChallenge(
                challengerId: userId, status: "accepted"),
               let matchId = accepted.matchId,
               !hasStartedMatch(matchId) {
                outgoingChallenge = accepted
                return
            }

            if outgoingChallenge?.status == "pending" || outgoingChallenge?.status == "accepted" {
                outgoingChallenge = nil
            }

            if outgoingChallenge == nil,
               let rejected = try await fetchLatestChallenge(
                challengerId: userId, status: "rejected") {
                outgoingChallenge = rejected
            }
        } catch {}
    }

    private func fetchLatestChallenge(
        challengerId: String,
        status: String
    ) async throws -> MatchChallengeInvite? {
        let data = try await SupabaseClient.shared.request(
            table: "match_challenges",
            query: "challenger_id=eq.\(challengerId)&status=eq.\(status)&order=updated_at.desc&limit=1&select=*")
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else { return nil }
        return await enrichWithUsernames(parseChallenge(row, challengerUsername: nil, opponentUsername: nil))
    }

    private func parseChallenge(
        _ row: [String: Any],
        challengerUsername: String?,
        opponentUsername: String?
    ) -> MatchChallengeInvite? {
        guard let id = row["id"] as? String,
              let challengerId = row["challenger_id"] as? String,
              let opponentId = row["opponent_id"] as? String,
              let status = row["status"] as? String,
              let seed = row["seed"] as? String else { return nil }
        return MatchChallengeInvite(
            id: id,
            challengerId: challengerId,
            opponentId: opponentId,
            challengerUsername: challengerUsername ?? "Player",
            opponentUsername: opponentUsername ?? "Player",
            status: status,
            seed: seed,
            matchId: row["match_id"] as? String)
    }
}
