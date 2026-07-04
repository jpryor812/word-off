import Foundation

/// Hidden AI opponent used when matchmaking can't find a human in time.
/// Skill tier 5–10 controls word strength and submission speed.
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
        let tier = Int.random(in: 5...10)
        let name = "\(namePrefixes.randomElement()!)\(nameSuffixes.randomElement()!)\(Int.random(in: 2...99))"
        return AIOpponent(username: name, tier: tier)
    }

    /// Picks a word and submission time for the given rack.
    /// - Returns: nil word on a whiff (low tiers sometimes fail entirely).
    func play(rack: [Character]) -> (word: String?, submitAt: TimeInterval) {
        let candidates = WordDictionary.shared.buildableWords(from: rack)
        guard !candidates.isEmpty else {
            return (nil, TimeInterval(GameConstants.roundSeconds))
        }

        // Low tiers occasionally fail to find any word.
        let whiffChance = max(0.0, 0.18 - Double(tier) * 0.016)
        if Double.random(in: 0...1) < whiffChance {
            return (nil, TimeInterval(GameConstants.roundSeconds))
        }

        let ranked = candidates
            .map { word -> (String, Int) in
                (word, Scoring.score(word: word, rackSize: rack.count, firstSubmit: false).total)
            }
            .sorted { $0.1 > $1.1 }

        // Tier maps to a percentile band of the ranked list. Tier 10 picks from
        // the top ~5%, tier 1 from around the 55th–90th percentile.
        let strength = Double(tier) / 10.0
        let bandTop = (1.0 - strength) * 0.55
        let bandBottom = min(0.95, bandTop + 0.35)
        let lower = Int(bandTop * Double(ranked.count - 1))
        let upper = max(lower, Int(bandBottom * Double(ranked.count - 1)))
        let chosen = ranked[Int.random(in: lower...upper)].0

        // Faster submissions at higher tiers, with jitter.
        let base = 17.0 - Double(tier) * 1.1        // tier 1 ≈ 15.9s, tier 10 ≈ 6s
        let submitAt = min(Double(GameConstants.roundSeconds) - 0.5,
                           max(3.0, base + Double.random(in: -2.0...2.5)))
        return (chosen, submitAt)
    }
}
