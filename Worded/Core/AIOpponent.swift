import Foundation

/// AI opponent used only when the player explicitly taps Play AI.
/// Skill tier 1–10 controls bingo frequency, word length, and submission speed.
struct AIOpponent {
    let username: String
    let tier: Int

    static let namePrefixes = [
        "Word", "Tile", "Lexi", "Vowel", "Quip", "Zesty", "Snappy", "Wiz",
        "Turbo", "Mellow", "Pixel", "Echo", "Nova", "Maple", "Coco", "Rocket",
        "Breezy", "Lucky", "Salty", "Dandy",
    ]
    static let nameSuffixes = [
        "Runner", "Smith", "Master", "Ninja", "Fox", "Bee", "Hawk", "Cat",
        "Dog", "Otter", "Player", "Champ", "Wolf", "Duck", "Moose", "Bear",
    ]

    static func random() -> AIOpponent {
        withTier(Int.random(in: 5...10))
    }

    /// Player-chosen difficulty (1 = easiest, 10 = hardest).
    static func withTier(_ tier: Int) -> AIOpponent {
        let clamped = min(10, max(1, tier))
        let name = "\(namePrefixes.randomElement()!)\(nameSuffixes.randomElement()!)\(Int.random(in: 2...99))"
        return AIOpponent(username: name, tier: clamped)
    }

    /// How many full-rack (8-letter) words this AI may play across a match.
    static func bingoQuota(for tier: Int) -> Int {
        switch min(10, max(1, tier)) {
        case 10: return 99          // essentially every round
        case 9: return Int.random(in: 3...4)
        case 7, 8: return Int.random(in: 1...3)
        case 5, 6: return Int.random(in: 0...2)
        default: return 0           // tier 1–4: never
        }
    }

    /// Picks a word and submission time for the given rack.
    /// - Parameter allowBingo: when false, never play an 8-letter word.
    /// Always submits a word when any buildable option exists.
    func play(rack: [Character], allowBingo: Bool) -> (word: String?, submitAt: TimeInterval) {
        let candidates = WordDictionary.shared.buildableWords(from: rack)
        guard !candidates.isEmpty else {
            return (nil, TimeInterval(GameConstants.roundSeconds))
        }

        let chosen = pickWord(from: candidates, rackSize: rack.count, allowBingo: allowBingo)
        return (chosen, submitTime())
    }

    // MARK: - Word selection

    private func pickWord(from candidates: [String], rackSize: Int, allowBingo: Bool) -> String {
        let bingos = candidates.filter { $0.count >= rackSize }
        let nonBingos = candidates.filter { $0.count < rackSize }

        if allowBingo, !bingos.isEmpty {
            return pickScored(from: bingos, preferTop: tier >= 9)
        }

        let (minLen, maxLen) = nonBingoLengthRange
        var pool = nonBingos.filter { $0.count >= minLen && $0.count <= maxLen }
        if pool.isEmpty {
            // Fall back to anything shorter than a bingo, then anything at all.
            pool = nonBingos
        }
        if pool.isEmpty {
            return pickScored(from: candidates, preferTop: false)
        }
        return pickScored(from: pool, preferTop: tier >= 7)
    }

    /// Preferred lengths when not playing a full-rack bingo.
    private var nonBingoLengthRange: (Int, Int) {
        switch tier {
        case 10: return (7, 7)
        case 9: return (6, 7)
        case 7, 8: return (5, 7)
        case 5, 6: return (4, 7)
        case 3, 4: return (4, 6)
        default: return (4, 5) // tier 1–2
        }
    }

    private func pickScored(from words: [String], preferTop: Bool) -> String {
        let ranked = words
            .map { word -> (String, Int) in
                (word, Scoring.score(word: word, rackSize: GameConstants.pvpRackSize, firstSubmit: false).total)
            }
            .sorted { $0.1 > $1.1 }
        guard ranked.count > 1 else { return ranked[0].0 }

        if preferTop {
            // Top 1–3 by score.
            let top = min(3, ranked.count) - 1
            return ranked[Int.random(in: 0...top)].0
        }

        // Mild randomness inside the length band — stronger tiers stay higher.
        let t = Double(tier) / 10.0
        let bandTop = (1.0 - t) * 0.35
        let bandWidth = max(0.15, 0.55 - t * 0.35)
        let last = ranked.count - 1
        let lower = Int((bandTop * Double(last)).rounded(.down))
        let upper = max(lower, Int((min(0.95, bandTop + bandWidth) * Double(last)).rounded(.down)))
        return ranked[Int.random(in: lower...upper)].0
    }

    // MARK: - Speed

    /// Tier 10 is brisk; 9 is slower; mid tiers vary widely.
    private func submitTime() -> TimeInterval {
        let range: ClosedRange<Double>
        switch tier {
        case 10: range = 5.0...10.0
        case 9: range = 7.0...16.0
        case 7, 8: range = 5.0...16.5
        case 5, 6: range = 7.0...18.0
        case 3, 4: range = 10.0...20.0
        default: range = 12.0...22.0
        }
        let raw = Double.random(in: range)
        return min(Double(GameConstants.roundSeconds) - 0.5, max(2.2, raw))
    }
}
