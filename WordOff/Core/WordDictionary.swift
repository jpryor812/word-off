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
            if count >= 2, count <= 12, !self.blocked.contains(word) {
                byLength[count, default: []].insert(word)
            }
        }
        wordsByLength = byLength
        isLoaded = true
    }

    /// Sorted word arrays per length, so seeded random picks are deterministic
    /// across devices (Set iteration order is not).
    private var sortedByLength: [Int: [String]] = [:]

    private func sortedWords(length: Int) -> [String] {
        if let cached = sortedByLength[length] { return cached }
        let sorted = (wordsByLength[length] ?? []).sorted()
        sortedByLength[length] = sorted
        return sorted
    }

    /// Builds a rack guaranteed to contain at least one word using ALL the
    /// letters: picks a real word of the full rack length and scrambles it.
    /// Among several candidates, prefers the rack whose letters can also form
    /// words at as many other lengths as possible.
    func makeRack(size: Int, rng: inout SeededRandom) -> [Character] {
        loadIfNeeded()
        let fullWords = sortedWords(length: size)
        guard !fullWords.isEmpty else {
            return LetterBag.drawRack(size: size, rng: &rng)
        }

        var best: (rack: [Character], coverage: Int)?
        let maxCoverage = size - 1   // lengths 2 through size

        for _ in 0..<6 {
            let word = fullWords[Int(rng.next() % UInt64(fullWords.count))]
            var letters = Array(word)
            for i in stride(from: letters.count - 1, to: 0, by: -1) {
                let j = Int(rng.next() % UInt64(i + 1))
                letters.swapAt(i, j)
            }
            // Don't hand the player the answer spelled out.
            if String(letters) == word {
                letters.swapAt(0, letters.count - 1)
            }
            let coverage = lengthCoverage(rack: letters)
            if coverage == maxCoverage { return letters }
            if best == nil || coverage > best!.coverage {
                best = (letters, coverage)
            }
        }
        return best!.rack
    }

    /// How many lengths (2...rack.count) have at least one buildable word.
    private func lengthCoverage(rack: [Character]) -> Int {
        var covered = 0
        for length in 2...rack.count {
            guard let words = wordsByLength[length] else { continue }
            for word in words where Scoring.isBuildable(word: word, from: rack) {
                covered += 1
                break
            }
        }
        return covered
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
