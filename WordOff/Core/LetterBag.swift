import Foundation

/// Scrabble-style letter frequencies and point values.
enum LetterBag {
    /// Standard Scrabble tile distribution (blanks excluded).
    static let distribution: [Character: Int] = [
        "A": 9, "B": 2, "C": 2, "D": 4, "E": 12, "F": 2, "G": 3, "H": 2,
        "I": 9, "J": 1, "K": 1, "L": 4, "M": 2, "N": 6, "O": 8, "P": 2,
        "Q": 1, "R": 6, "S": 4, "T": 6, "U": 4, "V": 2, "W": 2, "X": 1,
        "Y": 2, "Z": 1,
    ]

    /// Standard Scrabble letter values.
    static let values: [Character: Int] = [
        "A": 1, "B": 3, "C": 3, "D": 2, "E": 1, "F": 4, "G": 2, "H": 4,
        "I": 1, "J": 8, "K": 5, "L": 1, "M": 3, "N": 1, "O": 1, "P": 3,
        "Q": 10, "R": 1, "S": 1, "T": 1, "U": 1, "V": 4, "W": 4, "X": 8,
        "Y": 4, "Z": 10,
    ]

    static let vowels: Set<Character> = ["A", "E", "I", "O", "U"]

    private static let bag: [Character] = distribution.flatMap { letter, count in
        Array(repeating: letter, count: count)
    }.sorted()

    /// Draws a rack of `size` letters without replacement from a Scrabble bag,
    /// re-rolling until the rack has a playable vowel/consonant balance.
    static func drawRack(size: Int, rng: inout SeededRandom) -> [Character] {
        let minVowels = max(1, size / 4)          // 9 letters -> at least 2 vowels
        let maxVowels = max(minVowels + 1, (size * 2) / 3)
        for _ in 0..<64 {
            var pool = bag
            var rack: [Character] = []
            for _ in 0..<size {
                let idx = Int(rng.next() % UInt64(pool.count))
                rack.append(pool.remove(at: idx))
            }
            let vowelCount = rack.filter { vowels.contains($0) }.count
            if vowelCount >= minVowels && vowelCount <= maxVowels {
                return rack
            }
        }
        // Statistically unreachable, but guarantee a return.
        var pool = bag
        var rack: [Character] = []
        for _ in 0..<size {
            let idx = Int(rng.next() % UInt64(pool.count))
            rack.append(pool.remove(at: idx))
        }
        return rack
    }
}
