import Foundation

/// Loads the bundled ENABLE word list (2–9 letters) into per-length sets for
/// fast offline validation, and screens out profanity.
final class WordDictionary {
    static let shared = WordDictionary()

    private(set) var wordsByLength: [Int: Set<String>] = [:]
    private(set) var isLoaded = false

    /// Words that are valid English but never accepted or shown.
    private let blocked: Set<String> = [
        "SHIT", "SHITS", "FUCK", "FUCKS", "FUCKED", "FUCKER", "FUCKERS",
        "CUNT", "CUNTS", "BITCH", "BITCHES", "COCKS", "PRICKS", "TWAT",
        "TWATS", "WANK", "WANKS", "NIGGER", "NIGGERS", "FAGGOT", "FAGGOTS",
        "SPIC", "SPICS", "KIKE", "KIKES", "ASSHOLE", "ASSHOLES", "DAMN",
        "PISS", "PISSED", "PISSER", "TITS", "BOOBS", "DICKS", "SLUT", "SLUTS",
        "WHORE", "WHORES", "BASTARD", "BASTARDS",
    ]

    func loadIfNeeded() {
        guard !isLoaded else { return }
        guard let url = Bundle.main.url(forResource: "words", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("words.txt missing from bundle")
            return
        }
        var byLength: [Int: Set<String>] = [:]
        contents.enumerateLines { line, _ in
            let word = line.uppercased()
            let count = word.count
            if count >= 2, count <= 9, !self.blocked.contains(word) {
                byLength[count, default: []].insert(word)
            }
        }
        wordsByLength = byLength
        isLoaded = true
    }

    func contains(_ word: String) -> Bool {
        let upper = word.uppercased()
        return wordsByLength[upper.count]?.contains(upper) ?? false
    }

    /// All dictionary words buildable from `rack` (used by AI opponents).
    func buildableWords(from rack: [Character]) -> [String] {
        loadIfNeeded()
        var results: [String] = []
        for length in 2...rack.count {
            guard let words = wordsByLength[length] else { continue }
            for word in words where Scoring.isBuildable(word: word, from: rack) {
                results.append(word)
            }
        }
        return results
    }

    /// Validates a player submission against rack + dictionary.
    func validate(word: String, rack: [Character]) -> Bool {
        loadIfNeeded()
        let upper = word.uppercased()
        guard !upper.isEmpty else { return false }
        guard Scoring.isBuildable(word: upper, from: rack) else { return false }
        return contains(upper)
    }

    /// Basic profanity screen for usernames.
    func isCleanUsername(_ name: String) -> Bool {
        let upper = name.uppercased()
        return !blocked.contains { upper.contains($0) }
    }
}
