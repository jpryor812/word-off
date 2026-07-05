import Foundation

/// Builds and parses challenge invite links (`worded://challenge/{id}`).
enum ChallengeInviteLink {
    static let scheme = "worded"

    static func url(challengeId: String) -> URL {
        URL(string: "\(scheme)://challenge/\(challengeId)")!
    }

    /// Message body for SMS / iMessage / share sheet.
    static func shareMessage(challengerUsername: String, challengeId: String) -> String {
        "\(challengerUsername) challenged you to a Worded game! Tap to open: \(url(challengeId: challengeId).absoluteString)"
    }

    /// Parses `worded://challenge/{uuid}` and returns the challenge id.
    static func challengeId(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        if url.host == "challenge" {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        }
        // worded://challenge?id=uuid
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
            return id
        }
        return nil
    }

    /// Parses `worded://user/{username}` — opens the challenge flow for that player.
    static func username(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host == "user" else { return nil }
        let name = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return name.isEmpty ? nil : name
    }

    static func profileUrl(username: String) -> URL {
        URL(string: "\(scheme)://user/\(username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username)")!
    }

    static func profileShareMessage(username: String) -> String {
        "Challenge me on Worded! Tap to open the app: \(profileUrl(username: username).absoluteString)"
    }
}
