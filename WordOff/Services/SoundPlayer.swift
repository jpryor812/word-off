import Foundation
import AudioToolbox
import UIKit

/// Sound effects. Prefers custom audio files bundled in the app (drop
/// `whoosh.wav`, `flip.wav`, `tick.wav`, `win.wav`, `lose.wav`, `error.wav`,
/// or `fanfare.wav` — .caf/.aiff also work — into WordOff/Resources/Sounds/),
/// falling back to built-in iOS system sounds when a file isn't present.
final class SoundPlayer {
    static let shared = SoundPlayer()

    enum Effect: String, CaseIterable {
        case whoosh, flip, tick, win, lose, error, fanfare

        /// Fallback system sound when no custom file is bundled.
        var systemSoundID: SystemSoundID {
            switch self {
            case .whoosh: return 1001   // mail sent swoosh
            case .flip: return 1104     // soft keyboard tap
            case .tick: return 1306     // subtle key click
            case .win: return 1025      // positive chime
            case .lose: return 1053     // short low beep
            case .error: return 1053    // short negative beep
            case .fanfare: return 1025  // celebratory chime
            }
        }
    }

    var isEnabled = true

    private var customSoundIDs: [Effect: SystemSoundID] = [:]

    init() {
        // Register any bundled custom sound files up front.
        for effect in Effect.allCases {
            for ext in ["wav", "caf", "aiff", "mp3", "m4a"] {
                if let url = Bundle.main.url(forResource: effect.rawValue, withExtension: ext) {
                    var soundID: SystemSoundID = 0
                    if AudioServicesCreateSystemSoundID(url as CFURL, &soundID) == noErr {
                        customSoundIDs[effect] = soundID
                    }
                    break
                }
            }
        }
    }

    func play(_ effect: Effect) {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(customSoundIDs[effect] ?? effect.systemSoundID)
    }
}

/// Haptic feedback wrapper.
final class Haptics {
    private let generator = UIImpactFeedbackGenerator(style: .medium)

    func impact() {
        generator.impactOccurred()
    }
}
