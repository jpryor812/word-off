import Foundation

/// Deterministic RNG (SplitMix64) so every player worldwide gets identical
/// daily racks from the same seed.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    /// Builds a seed from an arbitrary string (e.g. "2026-07-03-daily-7-round-2").
    init(string: String) {
        var hash: UInt64 = 0xcbf29ce484222325 // FNV-1a
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        self.init(seed: hash)
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
