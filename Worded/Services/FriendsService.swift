import Foundation

enum FriendshipRelation: Equatable {
    case none
    case pendingOutgoing
    case pendingIncoming
    case friends
}

enum FriendsError: LocalizedError {
    case notConfigured
    case notSignedIn
    case userNotFound
    case cannotFriendSelf
    case alreadyFriends
    case alreadyPending

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Online play requires an internet connection and account."
        case .notSignedIn:
            return "Sign in to add friends."
        case .userNotFound:
            return "No player found with that username."
        case .cannotFriendSelf:
            return "You can't add yourself as a friend."
        case .alreadyFriends:
            return "You're already friends."
        case .alreadyPending:
            return "A friend request is already pending."
        }
    }
}

struct FriendRow: Identifiable, Equatable {
    let id: String
    let username: String
    let lastSeenAt: Date?

    /// Rough presence: seen within the last two minutes.
    var isOnline: Bool {
        guard let lastSeenAt else { return false }
        return Date().timeIntervalSince(lastSeenAt) < 120
    }
}

struct FriendRequestRow: Identifiable, Equatable {
    let id: String
    let requesterId: String
    let addresseeId: String
    let otherUserId: String
    let otherUsername: String
    let isIncoming: Bool
}

/// Mutual friendships, friend requests, and presence heartbeats.
@MainActor
final class FriendsService: ObservableObject {
    @Published private(set) var friends: [FriendRow] = []
    @Published private(set) var incomingRequests: [FriendRequestRow] = []
    @Published private(set) var outgoingRequests: [FriendRequestRow] = []
    /// Banner-worthy incoming request (newest); cleared after accept/deny/dismiss.
    @Published var bannerRequest: FriendRequestRow?

    private var heartbeatTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var dismissedBannerIds: Set<String> = []

    private static let onlineWindow: TimeInterval = 120
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func start() {
        guard SupabaseConfig.isConfigured, SupabaseClient.shared.currentSession != nil else { return }
        startHeartbeat()
        startPolling()
        Task { await refresh() }
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        pollTask?.cancel()
        pollTask = nil
    }

    func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pingPresence()
                try? await Task.sleep(for: .seconds(45))
            }
        }
    }

    func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func refresh() async {
        guard SupabaseConfig.isConfigured,
              let session = SupabaseClient.shared.currentSession else {
            friends = []
            incomingRequests = []
            outgoingRequests = []
            return
        }
        do {
            let rows = try await fetchFriendshipRows(for: session.userId)
            var friendIds: [String] = []
            var incoming: [FriendRequestRow] = []
            var outgoing: [FriendRequestRow] = []

            for row in rows {
                let otherId = row.requester == session.userId ? row.addressee : row.requester
                if row.status == "accepted" {
                    friendIds.append(otherId)
                } else if row.status == "pending" {
                    let isIncoming = row.addressee == session.userId
                    let request = FriendRequestRow(
                        id: "\(row.requester)|\(row.addressee)",
                        requesterId: row.requester,
                        addresseeId: row.addressee,
                        otherUserId: otherId,
                        otherUsername: otherId,
                        isIncoming: isIncoming)
                    if isIncoming {
                        incoming.append(request)
                    } else {
                        outgoing.append(request)
                    }
                }
            }

            let profiles = try await fetchProfiles(ids: Array(Set(friendIds + incoming.map(\.otherUserId) + outgoing.map(\.otherUserId))))
            let byId = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

            friends = friendIds.compactMap { id in
                guard let p = byId[id] else { return nil }
                return FriendRow(id: p.id, username: p.username, lastSeenAt: p.lastSeenAt)
            }
            .sorted { lhs, rhs in
                if lhs.isOnline != rhs.isOnline { return lhs.isOnline && !rhs.isOnline }
                return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
            }

            incomingRequests = incoming.map { req in
                FriendRequestRow(
                    id: req.id,
                    requesterId: req.requesterId,
                    addresseeId: req.addresseeId,
                    otherUserId: req.otherUserId,
                    otherUsername: byId[req.otherUserId]?.username ?? "Player",
                    isIncoming: true)
            }
            outgoingRequests = outgoing.map { req in
                FriendRequestRow(
                    id: req.id,
                    requesterId: req.requesterId,
                    addresseeId: req.addresseeId,
                    otherUserId: req.otherUserId,
                    otherUsername: byId[req.otherUserId]?.username ?? "Player",
                    isIncoming: false)
            }

            if let newest = incomingRequests.first(where: { !dismissedBannerIds.contains($0.id) }) {
                if bannerRequest?.id != newest.id {
                    bannerRequest = newest
                }
            } else if let current = bannerRequest, !incomingRequests.contains(where: { $0.id == current.id }) {
                bannerRequest = nil
            }
        } catch {
            // Keep last known state on transient failures.
        }
    }

    func relation(withUserId userId: String) -> FriendshipRelation {
        if friends.contains(where: { $0.id == userId }) { return .friends }
        if outgoingRequests.contains(where: { $0.otherUserId == userId }) { return .pendingOutgoing }
        if incomingRequests.contains(where: { $0.otherUserId == userId }) { return .pendingIncoming }
        return .none
    }

    func relation(withUsername username: String) -> FriendshipRelation {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if friends.contains(where: { $0.username.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .friends
        }
        if outgoingRequests.contains(where: { $0.otherUsername.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .pendingOutgoing
        }
        if incomingRequests.contains(where: { $0.otherUsername.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .pendingIncoming
        }
        return .none
    }

    func sendRequest(toUsername username: String) async throws {
        guard SupabaseConfig.isConfigured else { throw FriendsError.notConfigured }
        guard let session = SupabaseClient.shared.currentSession else { throw FriendsError.notSignedIn }

        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WordDictionary.shared.isCleanUsername(trimmed) else { throw FriendsError.userNotFound }
        guard let profile = try await fetchProfile(username: trimmed) else {
            throw FriendsError.userNotFound
        }
        try await sendRequest(toUserId: profile.id, myUserId: session.userId)
    }

    func sendRequest(toUserId userId: String) async throws {
        guard SupabaseConfig.isConfigured else { throw FriendsError.notConfigured }
        guard let session = SupabaseClient.shared.currentSession else { throw FriendsError.notSignedIn }
        try await sendRequest(toUserId: userId, myUserId: session.userId)
    }

    private func sendRequest(toUserId userId: String, myUserId: String) async throws {
        guard userId != myUserId else { throw FriendsError.cannotFriendSelf }

        switch relation(withUserId: userId) {
        case .friends: throw FriendsError.alreadyFriends
        case .pendingOutgoing, .pendingIncoming: throw FriendsError.alreadyPending
        case .none: break
        }

        // Also check reverse row that refresh may not have classified yet.
        if try await hasRow(between: myUserId, and: userId) {
            throw FriendsError.alreadyPending
        }

        let payload: [String: Any] = [
            "requester": myUserId,
            "addressee": userId,
            "status": "pending",
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await SupabaseClient.shared.request(
            table: "friendships",
            method: "POST",
            body: body,
            prefer: "return=minimal")
        let fromName = UserDefaults.standard.string(forKey: "worded.username") ?? "Someone"
        Task {
            await PushNotify.friendRequest(toUserId: userId, fromUsername: fromName)
        }
        await refresh()
    }

    func acceptRequest(_ request: FriendRequestRow) async throws {
        guard request.isIncoming else { return }
        let payload: [String: Any] = ["status": "accepted"]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await SupabaseClient.shared.request(
            table: "friendships",
            method: "PATCH",
            query: "requester=eq.\(request.requesterId)&addressee=eq.\(request.addresseeId)&status=eq.pending",
            body: body)
        dismissedBannerIds.insert(request.id)
        if bannerRequest?.id == request.id { bannerRequest = nil }
        await refresh()
    }

    func denyRequest(_ request: FriendRequestRow) async throws {
        _ = try await SupabaseClient.shared.request(
            table: "friendships",
            method: "DELETE",
            query: "requester=eq.\(request.requesterId)&addressee=eq.\(request.addresseeId)")
        dismissedBannerIds.insert(request.id)
        if bannerRequest?.id == request.id { bannerRequest = nil }
        await refresh()
    }

    func dismissBannerRequest() {
        if let id = bannerRequest?.id {
            dismissedBannerIds.insert(id)
        }
        bannerRequest = nil
    }

    func friendUserIds() -> Set<String> {
        Set(friends.map(\.id))
    }

    func friendUsernames() -> Set<String> {
        Set(friends.map { $0.username.lowercased() })
    }

    // MARK: - Presence

    func pingPresence() async {
        guard let session = SupabaseClient.shared.currentSession else { return }
        let now = Self.isoFractional.string(from: Date())
        guard let body = try? JSONSerialization.data(withJSONObject: ["last_seen_at": now]) else { return }
        _ = try? await SupabaseClient.shared.request(
            table: "profiles",
            method: "PATCH",
            query: "id=eq.\(session.userId)",
            body: body)
    }

    // MARK: - Private

    private struct FriendshipRow {
        let requester: String
        let addressee: String
        let status: String
    }

    private struct ProfilePresence {
        let id: String
        let username: String
        let lastSeenAt: Date?
    }

    private func fetchFriendshipRows(for userId: String) async throws -> [FriendshipRow] {
        let q = "or=(requester.eq.\(userId),addressee.eq.\(userId))&select=requester,addressee,status"
        let data = try await SupabaseClient.shared.request(table: "friendships", query: q)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let requester = row["requester"] as? String,
                  let addressee = row["addressee"] as? String,
                  let status = row["status"] as? String else { return nil }
            return FriendshipRow(requester: requester, addressee: addressee, status: status)
        }
    }

    private func hasRow(between a: String, and b: String) async throws -> Bool {
        let q = "or=(and(requester.eq.\(a),addressee.eq.\(b)),and(requester.eq.\(b),addressee.eq.\(a)))&select=requester"
        let data = try await SupabaseClient.shared.request(table: "friendships", query: q)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return false }
        return !rows.isEmpty
    }

    private func fetchProfile(username: String) async throws -> ProfilePresence? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let data = try await SupabaseClient.shared.request(
            table: "profiles",
            query: "username=eq.\(encoded)&select=id,username,last_seen_at")
        return try decodeProfiles(data).first
    }

    private func fetchProfiles(ids: [String]) async throws -> [ProfilePresence] {
        guard !ids.isEmpty else { return [] }
        // PostgREST `in` filter.
        let list = ids.joined(separator: ",")
        let data = try await SupabaseClient.shared.request(
            table: "profiles",
            query: "id=in.(\(list))&select=id,username,last_seen_at")
        return try decodeProfiles(data)
    }

    private func decodeProfiles(_ data: Data) throws -> [ProfilePresence] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseError.decoding
        }
        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let username = row["username"] as? String else { return nil }
            let lastSeen: Date?
            if let raw = row["last_seen_at"] as? String {
                lastSeen = Self.isoFractional.date(from: raw) ?? Self.isoBasic.date(from: raw)
            } else {
                lastSeen = nil
            }
            return ProfilePresence(id: id, username: username, lastSeenAt: lastSeen)
        }
    }
}
