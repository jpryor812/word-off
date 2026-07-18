import Foundation

/// Builds and parses challenge invite links.
/// Prefer HTTPS Universal Links (`https://worded.app/...`) so Texts open the app
/// or a web landing page / App Store. Custom `worded://` links still parse for
/// older shares.
enum ChallengeInviteLink {
    static let scheme = "worded"
    static let webHost = "worded.app"
    static let httpsBase = "https://\(webHost)"

    /// Universal Link used in SMS / share sheet.
    static func url(challengeId: String) -> URL {
        URL(string: "\(httpsBase)/challenge/\(challengeId)")!
    }

    /// Legacy custom-scheme URL (still accepted when opened).
    static func customSchemeURL(challengeId: String) -> URL {
        URL(string: "\(scheme)://challenge/\(challengeId)")!
    }

    /// Message body for SMS / iMessage / share sheet.
    static func shareMessage(challengerUsername: String, challengeId: String) -> String {
        "\(challengerUsername) challenged you to a Worded game! Tap to play: \(url(challengeId: challengeId).absoluteString)"
    }

    /// Parses challenge id from `https://worded.app/challenge/{uuid}` or `worded://challenge/...`.
    static func challengeId(from url: URL) -> String? {
        if let id = httpsChallengeId(from: url) { return id }
        return customSchemeChallengeId(from: url)
    }

    /// Parses `https://worded.app/user/{username}` or `worded://user/{username}`.
    static func username(from url: URL) -> String? {
        if let name = httpsUsername(from: url) { return name }
        return customSchemeUsername(from: url)
    }

    static func profileUrl(username: String) -> URL {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        return URL(string: "\(httpsBase)/user/\(encoded)")!
    }

    static func profileShareMessage(username: String) -> String {
        "Challenge me on Worded! Tap to open: \(profileUrl(username: username).absoluteString)"
    }

    // MARK: - HTTPS

    private static func httpsChallengeId(from url: URL) -> String? {
        guard isWordedWebHost(url) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0].lowercased() == "challenge" else { return nil }
        let id = parts[1]
        return id.isEmpty ? nil : id
    }

    private static func httpsUsername(from url: URL) -> String? {
        guard isWordedWebHost(url) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0].lowercased() == "user" else { return nil }
        let name = parts[1].removingPercentEncoding ?? parts[1]
        return name.isEmpty ? nil : name
    }

    private static func isWordedWebHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == webHost || host == "www.\(webHost)"
    }

    // MARK: - Custom scheme (legacy)

    private static func customSchemeChallengeId(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        if url.host == "challenge" {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
            return id
        }
        return nil
    }

    private static func customSchemeUsername(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host == "user" else { return nil }
        let name = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return name.isEmpty ? nil : name
    }
}
