import Foundation

struct ScoreBreakdown: Equatable, Codable {
    var letterPoints: Int = 0
    var lengthBonus: Int = 0
    var allLettersBonus: Int = 0
    var speedBonus: Int = 0

    var total: Int { letterPoints + lengthBonus + allLettersBonus + speedBonus }
}

enum Scoring {
    static let lengthBonusThreshold = 4   // +1 per letter beyond 4
    static let allLettersBonus = 5
    static let firstSubmitBonus = 2

    /// Scores a word already known to be valid. `rackSize` determines the
    /// all-letters bonus; `firstSubmit` adds the speed bonus.
    static func score(word: String, rackSize: Int, firstSubmit: Bool) -> ScoreBreakdown {
        var breakdown = ScoreBreakdown()
        let upper = word.uppercased()
        breakdown.letterPoints = upper.reduce(0) { $0 + (LetterBag.values[$1] ?? 0) }
        breakdown.lengthBonus = max(0, upper.count - lengthBonusThreshold)
        breakdown.allLettersBonus = upper.count == rackSize ? allLettersBonus : 0
        breakdown.speedBonus = firstSubmit ? firstSubmitBonus : 0
        return breakdown
    }

    /// True if `word` can be assembled from `rack`, each tile used at most once.
    static func isBuildable(word: String, from rack: [Character]) -> Bool {
        guard !word.isEmpty else { return false }
        var counts: [Character: Int] = [:]
        for letter in rack { counts[letter, default: 0] += 1 }
        for letter in word.uppercased() {
            guard let remaining = counts[letter], remaining > 0 else { return false }
            counts[letter] = remaining - 1
        }
        return true
    }
}
