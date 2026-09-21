import AppKit
import AudioToolbox

/// v0.8.1 R59, R60: a tap under the finger and the two sounds. The sounds become system sound
/// ids once, here, so nothing is read from disk at play time; each call checks its switch then.
@MainActor
final class Feedback {
    enum Sound: String, CaseIterable, Sendable {
        case landed, missed
    }

    /// What a tap and a sound do, and the clock the gate reads. Tests replace them to count.
    var perform: @MainActor (NSHapticFeedbackManager.FeedbackPattern) -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform($0, performanceTime: .drawCompleted)
    }
    var playSound: @MainActor (SystemSoundID) -> Void = { AudioServicesPlaySystemSoundWithCompletion($0, nil) }
    var now: @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    private let preferences: Preferences
    private let soundIDs: [Sound: SystemSoundID]
    private var gate = TapGate(spacing: DesignTokens.hover)

    init(preferences: Preferences, bundle: Bundle = .main) {
        self.preferences = preferences
        var ids: [Sound: SystemSoundID] = [:]
        for sound in Sound.allCases {
            var id: SystemSoundID = 0
            if let url = Self.url(for: sound, in: bundle), AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError {
                ids[sound] = id
            }
        }
        soundIDs = ids
    }

    deinit {
        for id in soundIDs.values { AudioServicesDisposeSystemSoundID(id) }
    }

    /// R59: lands with the frame that draws the change. macOS plays it only on a Force Touch
    /// trackpad with a finger on it, and drops it otherwise.
    func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard preferences.trackpadTaps, gate.admit(at: now()) else { return }
        perform(pattern)
    }

    /// R59: the trackpad has just clicked under the finger; no tap for the next 80 ms.
    func clicked() {
        gate.hold(at: now())
    }

    /// R60: one event in two channels — the sound and a tap of its own, fired together, the way
    /// Apple pairs audio with haptics. Each channel follows its own switch. This tap marks the
    /// capture rather than a move of the outline, so it does not wait for the ratchet gate; it
    /// holds the gate instead, keeping the next outline tap 80 ms clear of it.
    func play(_ sound: Sound) {
        if preferences.sounds, let id = soundIDs[sound] { playSound(id) }
        guard preferences.trackpadTaps else { return }
        gate.hold(at: now())
        perform(sound == .landed ? .generic : .levelChange)
    }

    /// The rendered file (`design/sound/render ship`); Xcode copies it flat into Resources.
    nonisolated static func url(for sound: Sound, in bundle: Bundle) -> URL? {
        bundle.url(forResource: sound.rawValue, withExtension: "caf")
    }
}
