import Foundation

/// Hidden AI opponent used when the player chooses Play AI (or offline).
/// Skill tier 1–10 controls word strength and submission speed.
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

    /// Picks a word and submission time for the given rack.
    /// - Returns: nil word on a whiff (low tiers sometimes fail entirely).
    func play(rack: [Character]) -> (word: String?, submitAt: TimeInterval) {
        let candidates = WordDictionary.shared.buildableWords(from: rack)
        guard !candidates.isEmpty else {
            return (nil, TimeInterval(GameConstants.roundSeconds))
        }

        // Only the easiest difficulties whiff; 5+ almost never blank a round.
        let whiffChance = max(0.0, 0.22 - Double(tier) * 0.045)
        if Double.random(in: 0...1) < whiffChance {
            return (nil, TimeInterval(GameConstants.roundSeconds))
        }

        let ranked = candidates
            .map { word -> (String, Int) in
                (word, Scoring.score(word: word, rackSize: rack.count, firstSubmit: false).total)
            }
            .sorted { $0.1 > $1.1 }

        let chosen = pickWord(from: ranked)

        // Higher tiers submit early to contest the +1 speed bonus.
        // Tier 1 ≈ 16s, tier 7 ≈ 5.5s, tier 10 ≈ 3s.
        let base = 17.5 - Double(tier) * 1.45
        let submitAt = min(Double(GameConstants.roundSeconds) - 0.5,
                           max(2.5, base + Double.random(in: -1.2...1.2)))
        return (chosen, submitAt)
    }

    /// Stronger curve than before: mid/high tiers stay near the top of the
    /// scored word list instead of drifting into mediocre mid-pack words.
    private func pickWord(from ranked: [(String, Int)]) -> String {
        let last = max(ranked.count - 1, 0)
        guard last > 0 else { return ranked[0].0 }

        let t = Double(tier) / 10.0
        // Lift mid tiers (7/10 used to feel like ~4/10).
        let skill = pow(t, 0.55)

        // Often just take the best available word at higher difficulties.
        let snapBestChance = min(0.92, skill * skill * 1.15)
        if Double.random(in: 0...1) < snapBestChance {
            return ranked[0].0
        }

        // Otherwise pick inside a narrow top band that shrinks with skill.
        // Tier 1: ~top 40–85%. Tier 7: ~top 0–12%. Tier 10: ~top 0–4%.
        let bandTop = (1.0 - skill) * 0.40
        let bandWidth = max(0.03, 0.50 - skill * 0.48)
        let bandBottom = min(0.95, bandTop + bandWidth)

        let lower = Int((bandTop * Double(last)).rounded(.down))
        let upper = max(lower, Int((bandBottom * Double(last)).rounded(.down)))
        return ranked[Int.random(in: lower...upper)].0
    }
}
