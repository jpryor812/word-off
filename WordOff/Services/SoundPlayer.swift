import Foundation
import AudioToolbox
import UIKit

/// Lightweight sound effects using system sounds (no bundled audio needed for v1).
final class SoundPlayer {
    static let shared = SoundPlayer()

    enum Effect {
        case whoosh, flip, tick, win, lose, fanfare

        var systemSoundID: SystemSoundID {
            switch self {
            case .whoosh: return 1004   // swoosh-like
            case .flip: return 1104     // keyboard tap
            case .tick: return 1103     // tick
            case .win: return 1025      // positive chime
            case .lose: return 1073     // low tone
            case .fanfare: return 1335  // celebratory
            }
        }
    }

    var isEnabled = true

    func play(_ effect: Effect) {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(effect.systemSoundID)
    }
}

/// Haptic feedback wrapper.
final class Haptics {
    private let generator = UIImpactFeedbackGenerator(style: .medium)

    func impact() {
        generator.impactOccurred()
    }
}
