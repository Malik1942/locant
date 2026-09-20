# Trackpad taps and two sounds (v0.8.1 R59–R62) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A light trackpad tap when Locant's outline moves to a new element, when Option steps a level, when the ring opens and between its segments; a soft `landed` sound when a capture reaches the clipboard and a lower `missed` when nothing did; a switch for each in Settings › General.

**Architecture:** One `Feedback` object, owned by `AppState` like the toast and handed to the ball, wraps `NSHapticFeedbackManager` (taps) and AudioToolbox system sounds (two bundled CAF files made by `design/sound/render.swift`). Two pure structs decide when a tap may play: `TapGate` (at most one per 80 ms, held after a click) and `OutlineMoves` (did the drawn outline move). `AppState` and `FloatingBall` call `tap` and `play` at the moments the spec lists; `Preferences` holds the two switches; `SelectionOverlay.setHighlight` reports whether it drew, so nothing taps while a frame is dragged.

**Tech Stack:** Swift 6 (strict concurrency `complete`), AppKit, SwiftUI, AudioToolbox (new, approved Sep 19, 2026), XCTest. macOS 15.0 deployment target.

**Revision:** Sep 19, 2026, after a five-agent review: a dry run of Tasks 2–8 on PR #38 (170 tests green once `TapGate` stopped reading a main-actor token), a behavior review, a conventions review, and two reviews of the sounds. Their accepted findings are folded in below.

## Global Constraints

- The spec is `specs/v0.8.1.md` (R59 taps, R60 sounds, R61 Settings, R62 sentences). Paste into the agent is R63 in `specs/v0.8.1-paste.md`: never edit that file, never add an R63 here.
- Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`, `MACOSX_DEPLOYMENT_TARGET = 15.0`: no `isolated deinit` (needs a newer runtime). `DesignTokens` is `@MainActor`: a nonisolated type must not read it in a stored-property default.
- Frameworks: Foundation, AppKit, SwiftUI, ScreenCaptureKit, Vision, ApplicationServices, and AudioToolbox. In the app only `Locant/Feedback/Feedback.swift` imports AudioToolbox; `LocantTests/FeedbackTests.swift` uses it to check the shipped files (spec §3). No third-party packages.
- One `@Observable` `AppState`, no other singletons: `Feedback` is created in `AppState.start()` and handed to the ball.
- Taps: `NSHapticFeedbackManager.defaultPerformer.perform(_:performanceTime: .drawCompleted)`; patterns `.alignment` (outline moves, ring segments), `.levelChange` (Option), `.generic` (ring opens); at most one per 80 ms (`DesignTokens.hover`); only for an outline actually drawn; an edge shift of 2 pt or less is not a move; never on a click, and a click on the overlay holds the gate for 80 ms.
- Sounds: `landed`, `missed`; mono, 48 kHz, 24-bit linear PCM CAF, at most 250 ms; `landed` peaks at −18 dBFS ± 1 dB, `missed` 3 dB lower; played with `AudioServicesPlaySystemSoundWithCompletion`; `kAudioServicesPropertyIsUISound` left at its default.
- Settings copy, verbatim: "Trackpad taps" / "A light tap under your finger when the outline moves to a new element, when the ring opens, and between its segments. Needs a Force Touch trackpad." and "Sounds" / "A soft sound when a capture reaches the clipboard, a lower one when nothing did. Follows Play user interface sound effects in Sound settings."
- `docs/CLAUDE.md`: commit messages `area: what changed`, one intent each; never commit without a green build; match the surrounding comment density; doc comments cite the requirement (`v0.8.1 R59`); do not reformat untouched code; the README is written in the last slot.
- Build and test commands (from the worktree root; `build/` is git-ignored):
  - Build: `xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -derivedDataPath build/dd build 2>&1 | tail -3` → ends with `** BUILD SUCCEEDED **`
  - One test class: `xcodebuild test -project Locant.xcodeproj -scheme Locant -derivedDataPath build/dd -only-testing:LocantTests/FeedbackTests 2>&1 | grep -E "Test Case|error:|TEST (SUCCEEDED|FAILED)" | tail -20`
  - All tests: `xcodebuild test -project Locant.xcodeproj -scheme Locant -derivedDataPath build/dd 2>&1 | grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)" | tail -5`
  - New warnings in touched files (run on a command that compiles them, i.e. a test run right after the edit): `… 2>&1 | grep -E "(Feedback|TapGate|AppState|FloatingBall|SelectionOverlay|SettingsView|Preferences)(Tests)?\.swift:[0-9]+:[0-9]+: warning:"` prints nothing.
- The test host is Locant itself, so `Bundle.main` in a test is the app bundle.
- `$SCRATCH` is a folder outside the repo for throwaway output (the session scratchpad); set it before the commands that use it.

## Prerequisite: on main with PR #38 and #37 (done Sep 19, 2026)

The branch was rebased onto `origin/main` at `edf1986` (PR #38 paste into the agent, PR #37 after-images). `Preferences.pastesIntoAgent` sits after `checksForUpdates`; `commit(note:)` ends with `if preferences.pastesIntoAgent { await pasteIntoAgent(near: anchor) } else { showAgentHintIfNeeded() }`; `isolatedDefaults()` is an `XCTestCase` extension returning `InMemoryDefaults` (use it for every new preferences test; never create a `UserDefaults` suite). If `origin/main` has moved again before a task starts, `git fetch origin && git rebase origin/main` first and re-run the build.

---

### Task 1: The sound renderer and three candidate sets (closes nothing yet; Task 8 closes spec slot 1)

**Status:** renderer `cecb7bb`, tuned after review `8d7c86d`; candidates rendered, measured, and published for listening (https://claude.ai/artifact/UHh3hJEj4kBn9ArZ8djZ23, version 2). Remaining: Malik names a set.

**Files:**
- Create: `design/sound/render.swift` (done), `.gitignore` line `design/sound/render` (done)

**Interfaces:**
- Produces: `design/sound/render candidates <folder>` (WAV per set and sound) and `design/sound/render ship <glass|wood|felt>` (writes `Locant/Feedback/Sounds/landed.caf` and `missed.caf`, run from the repo root). Every parameter is in `sets` and the constants below it in `render.swift`.

- [x] **Step 1: Write `design/sound/render.swift`**: modal synthesis, SplitMix64 noise through RBJ biquads for the mallet, 2 ms raised-cosine attack, 40 ms raised-cosine fade to zero, peak normalization, 24-bit WAV writer, `afconvert` to CAF, a 16 384-point DFT for the band share.
- [x] **Step 2: Tune after review**: glass twin 1.009/0.45 → 1.0035/0.25 (the 6–8 Hz wobble is gone, no re-swell over 0.6 dB); every decay shortened so the tail is 20 to 33 dB down when the fade starts (it was 14 to 21); audible mallets on glass (touch 0.6, 4 ms) and wood (1.0, 4 ms); richer felt harmonics; `missed` 250 ms.
- [x] **Step 3: Render and measure**

```bash
swiftc -O design/sound/render.swift -o design/sound/render
design/sound/render candidates "$SCRATCH/candidates"
```

```
glass-landed   250 ms   peak  -18.0 dBFS   rms  -29.5 dBFS   500 Hz–5 kHz  99.9 %
glass-missed   250 ms   peak  -21.0 dBFS   rms  -34.1 dBFS   500 Hz–5 kHz  99.0 %
wood-landed    250 ms   peak  -18.0 dBFS   rms  -29.3 dBFS   500 Hz–5 kHz  99.8 %
wood-missed    250 ms   peak  -21.0 dBFS   rms  -34.4 dBFS   500 Hz–5 kHz  98.7 %
felt-landed    250 ms   peak  -18.0 dBFS   rms  -28.6 dBFS   500 Hz–5 kHz  99.9 %
felt-missed    250 ms   peak  -21.0 dBFS   rms  -33.2 dBFS   500 Hz–5 kHz  99.0 %
```

- [ ] **Step 4: Malik names a set** (or asks for changes: edit `sets`, re-render, rebuild the page, republish). Task 8 needs the name.

---

### Task 2: `TapGate` and `OutlineMoves` (pure, R59)

**Files:**
- Create: `Locant/Feedback/TapGate.swift`
- Create: `LocantTests/FeedbackTests.swift`

**Interfaces:**
- Produces: `struct TapGate { let spacing: TimeInterval; init(spacing: TimeInterval); mutating func admit(at now: TimeInterval) -> Bool; mutating func hold(at now: TimeInterval) }` — nonisolated; callers pass `DesignTokens.hover`.
- Produces: `struct OutlineMoves { static let drift: CGFloat; mutating func moved(to frame: CGRect?) -> Bool }` (init `OutlineMoves()`).

- [ ] **Step 1: Write the failing tests** in `LocantTests/FeedbackTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import Locant

@MainActor
final class FeedbackTests: XCTestCase {
    // v0.8.1 R59: one tap per 80 ms, measured from the last tap let through; either side of the edge.
    func testTapGateSpacesTapsEightyMillisecondsApart() {
        var gate = TapGate(spacing: 0.080)
        XCTAssertTrue(gate.admit(at: 10.0))
        XCTAssertFalse(gate.admit(at: 10.0799))
        XCTAssertTrue(gate.admit(at: 10.0801))
        XCTAssertFalse(gate.admit(at: 10.1))
    }

    // R59: a dropped tap does not restart the interval, so a steady sweep keeps its rhythm.
    func testTapGateDroppedTapsDoNotRestartTheInterval() {
        var gate = TapGate(spacing: 0.080)
        XCTAssertTrue(gate.admit(at: 1.00))
        XCTAssertFalse(gate.admit(at: 1.05))
        XCTAssertTrue(gate.admit(at: 1.10), "100 ms after the last tap played, 50 ms after the dropped one")
    }

    // R59: hover redraws about every 33 ms; a sweep across small elements taps every third
    // redraw, evenly: a ratchet, not a buzz, not silence.
    func testTapGateAtHoverRateIsAnEvenRatchet() {
        var gate = TapGate(spacing: 0.080)
        let played = (0..<30).map { Double($0) * 0.033 }.filter { gate.admit(at: $0) }
        XCTAssertEqual(played.count, 10)
        for (a, b) in zip(played, played.dropFirst()) {
            XCTAssertEqual(b - a, 0.099, accuracy: 0.0001)
        }
    }

    // R59: a hold shuts the gate for 80 ms from the hold, as a tap would, without one.
    func testTapGateHoldShutsItFromTheHold() {
        var gate = TapGate(spacing: 0.080)
        XCTAssertTrue(gate.admit(at: 1.000))
        gate.hold(at: 1.030)
        XCTAssertFalse(gate.admit(at: 1.090), "90 ms after the tap, but 60 after the hold")
        XCTAssertTrue(gate.admit(at: 1.111))
    }

    // R59: the first outline is not a move; another frame is; the same frame again is not.
    func testOutlineMovesBetweenFrames() {
        var outline = OutlineMoves()
        let a = CGRect(x: 10, y: 10, width: 40, height: 20)
        let b = CGRect(x: 60, y: 10, width: 40, height: 20)
        XCTAssertFalse(outline.moved(to: a), "the first outline after the overlay opens")
        XCTAssertFalse(outline.moved(to: a))
        XCTAssertTrue(outline.moved(to: b))
        XCTAssertTrue(outline.moved(to: a))
    }

    // R59: onto the no-element square (nil) is not a move; off it onto an element is, even
    // when the square was the first outline or the element is the one before the square.
    func testOutlineMovesAroundTheNoElementSquare() {
        var outline = OutlineMoves()
        let a = CGRect(x: 10, y: 10, width: 40, height: 20)
        XCTAssertFalse(outline.moved(to: nil))
        XCTAssertTrue(outline.moved(to: a))
        XCTAssertFalse(outline.moved(to: nil))
        XCTAssertTrue(outline.moved(to: a))
        XCTAssertFalse(outline.moved(to: a))
    }

    // R59: an edge that shifts 2 pt or less, as a web card lifting under the pointer, is the
    // same outline; 3 pt is a move.
    func testOutlineMovesIgnoresADriftOfTwoPoints() {
        var outline = OutlineMoves()
        let card = CGRect(x: 100, y: 100, width: 200, height: 120)
        XCTAssertFalse(outline.moved(to: card))
        XCTAssertFalse(outline.moved(to: card.offsetBy(dx: 0, dy: -2)), "lifted 2 pt")
        XCTAssertFalse(outline.moved(to: card), "settled back")
        XCTAssertTrue(outline.moved(to: card.offsetBy(dx: 3, dy: 0)), "3 pt is a move")
    }
}
```

- [ ] **Step 2: Run them to see them fail.** One-class test command. Expected: build fails with `cannot find 'TapGate' in scope` and `cannot find 'OutlineMoves' in scope`.

- [ ] **Step 3: Write `Locant/Feedback/TapGate.swift`:**

```swift
import CoreGraphics
import Foundation

/// v0.8.1 R59: at most one tap per `spacing`, measured from the last tap let through. A dropped
/// tap neither restarts the interval nor plays later, so a fast sweep is an even ratchet.
struct TapGate {
    let spacing: TimeInterval
    private var last: TimeInterval?

    init(spacing: TimeInterval) {
        self.spacing = spacing
    }

    mutating func admit(at now: TimeInterval) -> Bool {
        if let last, now - last < spacing { return false }
        last = now
        return true
    }

    /// Shuts the gate for `spacing` from `now`, as a tap would, without one: a click is felt already.
    mutating func hold(at now: TimeInterval) {
        last = now
    }
}

/// v0.8.1 R59: whether the drawn outline moved. The first outline after the overlay opens is not
/// a move, nor is one onto the no-element square (nil), nor a drift of `drift` or less on every
/// edge; leaving the square for an element is.
struct OutlineMoves {
    /// A web card lifting under the pointer shifts about this much.
    static let drift: CGFloat = 2
    private var drawn = false
    private var last: CGRect?

    mutating func moved(to frame: CGRect?) -> Bool {
        defer { drawn = true; last = frame }
        guard drawn, let frame else { return false }
        guard let last else { return true }
        return abs(frame.minX - last.minX) > Self.drift || abs(frame.minY - last.minY) > Self.drift
            || abs(frame.maxX - last.maxX) > Self.drift || abs(frame.maxY - last.maxY) > Self.drift
    }
}
```

- [ ] **Step 4: Run the tests.** Same command. Expected: 7 tests pass, `** TEST SUCCEEDED **`, no new warnings (warnings grep from Global Constraints on the same output).
- [ ] **Step 5: Commit**

```bash
git add Locant/Feedback/TapGate.swift LocantTests/FeedbackTests.swift
git commit -m "feedback: TapGate spaces taps 80 ms apart and holds after a click; OutlineMoves says when the outline moved"
```

---

### Task 3: The two switches in `Preferences` (R61)

**Files:**
- Modify: `Locant/Store/Preferences.swift` (the `Key` enum, a property pair after `pastesIntoAgent`, `init`)
- Modify: `LocantTests/PreferencesTests.swift` (`testDefaultsWhenNothingStored`, `testRoundTripThroughDefaults`)

**Interfaces:**
- Produces: `Preferences.trackpadTaps: Bool` and `Preferences.sounds: Bool`, both default `true`, keys `"trackpadTaps"` and `"sounds"`.

- [ ] **Step 1: Write the failing assertions.** In `testDefaultsWhenNothingStored`, after `XCTAssertFalse(p.pastesIntoAgent)`:

```swift
        XCTAssertTrue(p.trackpadTaps)
        XCTAssertTrue(p.sounds)
```

In `testRoundTripThroughDefaults`, after `p.pastesIntoAgent = true`:

```swift
        p.trackpadTaps = false
        p.sounds = false
```

and after `XCTAssertTrue(again.pastesIntoAgent)`:

```swift
        XCTAssertFalse(again.trackpadTaps)
        XCTAssertFalse(again.sounds)
```

- [ ] **Step 2: Run to see it fail.** `-only-testing:LocantTests/PreferencesTests`. Expected: `value of type 'Preferences' has no member 'trackpadTaps'`.

- [ ] **Step 3: Implement.** In `enum Key`, after `static let pastesIntoAgent = "pastesIntoAgent" // v0.8.1 R63`:

```swift
        static let trackpadTaps = "trackpadTaps" // v0.8.1 R61
        static let sounds = "sounds" // v0.8.1 R61
```

After the `pastesIntoAgent` property:

```swift
    /// v0.8.1 R61: a tap under the finger as the outline moves, the ring opens, the segments pass.
    var trackpadTaps: Bool {
        didSet { defaults.set(trackpadTaps, forKey: Key.trackpadTaps) }
    }

    /// v0.8.1 R61: `landed` when a capture reaches the clipboard, `missed` when nothing did.
    var sounds: Bool {
        didSet { defaults.set(sounds, forKey: Key.sounds) }
    }
```

In `init`, after `pastesIntoAgent = defaults.object(forKey: Key.pastesIntoAgent) as? Bool ?? false`:

```swift
        trackpadTaps = defaults.object(forKey: Key.trackpadTaps) as? Bool ?? true
        sounds = defaults.object(forKey: Key.sounds) as? Bool ?? true
```

- [ ] **Step 4: Run the tests.** Same command. Expected: every `PreferencesTests` test passes, no new warnings.
- [ ] **Step 5: Commit**

```bash
git add Locant/Store/Preferences.swift LocantTests/PreferencesTests.swift
git commit -m "preferences: Trackpad taps and Sounds, both on by default"
```

---

### Task 4: `Feedback`, owned by `AppState` and handed to the ball (R59, R60, R62)

**Files:**
- Modify: `docs/CLAUDE.md:19` (its own commit, first)
- Create: `Locant/Feedback/Feedback.swift`
- Modify: `Locant/App/AppState.swift` (a property after `ball`; the first line of `start()`; `updateBall()`)
- Modify: `Locant/Launcher/FloatingBall.swift` (a property after `onAction`)
- Test: `LocantTests/FeedbackTests.swift`

**Interfaces:**
- Consumes: `TapGate(spacing:)`, `admit(at:)`, `hold(at:)` (Task 2); `Preferences.trackpadTaps`, `Preferences.sounds` (Task 3).
- Produces: `@MainActor final class Feedback { enum Sound: String, CaseIterable, Sendable { case landed, missed }; var perform: @MainActor (NSHapticFeedbackManager.FeedbackPattern) -> Void; var playSound: @MainActor (SystemSoundID) -> Void; var now: @MainActor () -> TimeInterval; init(preferences: Preferences, bundle: Bundle = .main); func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern); func clicked(); func play(_ sound: Sound); nonisolated static func url(for sound: Sound, in bundle: Bundle) -> URL? }`. `perform`, `playSound`, `now` default to the real calls; tests replace them.
- Produces: `AppState.feedback: Feedback?` (private) and `FloatingBall.feedback: Feedback?`.

- [ ] **Step 1: The framework line, committed alone.** In `docs/CLAUDE.md` replace
`- No third-party packages. Foundation, AppKit, SwiftUI, ScreenCaptureKit, Vision, ApplicationServices only.`
with
`- No third-party packages. Foundation, AppKit, SwiftUI, ScreenCaptureKit, Vision, ApplicationServices, and AudioToolbox (the two interface sounds, specs/v0.8.1.md R60) only.`

```bash
git add docs/CLAUDE.md
git commit -m "docs: AudioToolbox joins the allowed frameworks, for the two interface sounds"
```

- [ ] **Step 2: Write the failing tests** (append inside `FeedbackTests`):

```swift
    // R61: Trackpad taps is read at the moment of each tap. R59: the gate spaces them 80 ms.
    func testTapsFollowTheSwitchAndTheGate() {
        let preferences = Preferences(defaults: isolatedDefaults())
        let feedback = Feedback(preferences: preferences, bundle: Bundle(for: FeedbackTests.self))
        var clock: TimeInterval = 100
        var tapped: [NSHapticFeedbackManager.FeedbackPattern] = []
        feedback.now = { clock }
        feedback.perform = { tapped.append($0) }
        feedback.tap(.alignment)
        clock += 0.050
        feedback.tap(.alignment) // inside 80 ms: dropped
        clock += 0.040
        feedback.tap(.levelChange) // 90 ms after the first
        preferences.trackpadTaps = false
        clock += 0.200
        feedback.tap(.generic) // switched off
        preferences.trackpadTaps = true
        clock += 0.200
        feedback.tap(.generic)
        XCTAssertEqual(tapped, [.alignment, .levelChange, .generic])
    }

    // R59: a click is felt already, so the gate stays shut for 80 ms after it.
    func testAClickHoldsTheGate() {
        let feedback = Feedback(preferences: Preferences(defaults: isolatedDefaults()), bundle: Bundle(for: FeedbackTests.self))
        var clock: TimeInterval = 100
        var taps = 0
        feedback.now = { clock }
        feedback.perform = { _ in taps += 1 }
        feedback.clicked()
        clock += 0.050
        feedback.tap(.alignment)
        XCTAssertEqual(taps, 0)
        clock += 0.040
        feedback.tap(.alignment)
        XCTAssertEqual(taps, 1)
    }

    // R60: with no sound files (the test bundle has none) nothing loads and nothing plays.
    func testMissingSoundsPlayNothing() {
        let bundle = Bundle(for: FeedbackTests.self)
        for sound in Feedback.Sound.allCases {
            XCTAssertNil(Feedback.url(for: sound, in: bundle))
        }
        let feedback = Feedback(preferences: Preferences(defaults: isolatedDefaults()), bundle: bundle)
        var played = 0
        feedback.playSound = { _ in played += 1 }
        feedback.play(.landed)
        feedback.play(.missed)
        XCTAssertEqual(played, 0)
    }
```

- [ ] **Step 3: Run to see them fail.** One-class test command. Expected: `cannot find 'Feedback' in scope`.

- [ ] **Step 4: Write `Locant/Feedback/Feedback.swift`:**

```swift
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

    /// R60: at once, with the toast. `kAudioServicesPropertyIsUISound` stays at its default, so
    /// the system keeps it silent while Play user interface sound effects is off.
    func play(_ sound: Sound) {
        guard preferences.sounds, let id = soundIDs[sound] else { return }
        playSound(id)
    }

    /// The rendered file (`design/sound/render ship`); Xcode copies it flat into Resources.
    nonisolated static func url(for sound: Sound, in bundle: Bundle) -> URL? {
        bundle.url(forResource: sound.rawValue, withExtension: "caf")
    }
}
```

- [ ] **Step 5: Own it in `AppState` and hand it to the ball.** In `AppState`, after `@ObservationIgnored private var ball: FloatingBall?`:

```swift
    /// v0.8.1 R59, R60: taps and sounds; made in `start()`, before the ball that shares it.
    @ObservationIgnored private var feedback: Feedback?
```

As the first line of `start()`:

```swift
        feedback = Feedback(preferences: preferences)
```

In `updateBall()`, after `newBall.ringHints = ringHints()`:

```swift
            newBall.feedback = feedback
```

In `FloatingBall`, after the `onAction` property:

```swift
    /// v0.8.1 R59: taps as the ring opens and as the pointer crosses into another segment.
    var feedback: Feedback?
```

- [ ] **Step 6: Run the tests.** One-class command → 10 `FeedbackTests` pass; the warnings grep on that output prints nothing. Then all tests → `** TEST SUCCEEDED **`.
- [ ] **Step 7: Commit**

```bash
git add Locant/Feedback/Feedback.swift Locant/App/AppState.swift Locant/Launcher/FloatingBall.swift LocantTests/FeedbackTests.swift
git commit -m "feedback: taps and system sounds behind their switches, owned by AppState and shared with the ball"
```

---

### Task 5: The taps (R59)

**Files:**
- Modify: `Locant/Capture/SelectionOverlay.swift` (`SelectionOverlay.setHighlight`, `OverlayContentView.showHighlight`)
- Modify: `Locant/App/AppState.swift` (a property; `drainHover()`; `renderHover()`; `optionPressed()`; `click(_:shift:)`; `reset()`)
- Modify: `Locant/Launcher/FloatingBall.swift` (`pressBegan()`, `pressMoved(to:)`)

**Interfaces:**
- Consumes: `OutlineMoves.moved(to:)` (Task 2), `Feedback.tap(_:)`, `Feedback.clicked()`, `AppState.feedback`, `FloatingBall.feedback` (Task 4), `Ring.hovered` and `Ring.hover(at:optionHeld:) -> Segment?` (existing).
- Produces: `@discardableResult SelectionOverlay.setHighlight(_:readout:around:) -> Bool` and `@discardableResult OverlayContentView.showHighlight(screenRect:readout:) -> Bool` — true when an outline was drawn. Existing callers ignore the result.

- [ ] **Step 1: The overlay says whether it drew.** In `OverlayContentView`, replace the signature and guard of `showHighlight` and return at its end:

```swift
    /// v0.8.1 R59: false when nothing was drawn (a frame is being dragged or adjusted), so no tap marks it.
    @discardableResult
    func showHighlight(screenRect: CGRect, readout: Readout) -> Bool {
        guard let window, !isDragging, !isAdjusting else { return false }
```

and after its last line, `highlight.needsDisplay = true`:

```swift
        return true
```

In `SelectionOverlay`, replace `setHighlight` (keep its existing doc comment line above it and add the second line):

```swift
    /// v0.8.1 R59: true when an outline was drawn.
    @discardableResult
    func setHighlight(_ frame: CGRect?, readout: Readout, around point: CGPoint) -> Bool {
        let rect = Geometry.appKitRect(fromCG: frame ?? Self.fallbackRect(around: point), primaryHeight: primaryHeight)
        let target = panel(containing: rect)
        var drawn = false
        for panel in panels {
            if panel === target {
                drawn = panel.contentOverlay.showHighlight(screenRect: rect, readout: readout)
            } else {
                panel.contentOverlay.hideHighlight()
            }
        }
        return drawn
    }
```

- [ ] **Step 2: The property.** In `AppState`, after `@ObservationIgnored private var levelIndex = 0`:

```swift
    /// v0.8.1 R59: whether the drawn outline moved since the last redraw; reset with each session.
    @ObservationIgnored private var outlineMoves = OutlineMoves()
```

- [ ] **Step 3: A hover left over from the last session draws nothing.** In `drainHover()`, change the loop header `while phase == .hovering, let point = pendingHover {` to

```swift
        while phase == .hovering, !Task.isCancelled, let point = pendingHover {
```

and the guard right after `let fresh = await reader.snapshot(…)`, `guard phase == .hovering else { return }`, to

```swift
            guard phase == .hovering, !Task.isCancelled else { return }
```

- [ ] **Step 4: Snap and Cut: a new window under the cursor taps.** In `drainHover()`, replace

```swift
                lastHoverPoint = point
                if let window = Geometry.windowOwner(at: point, windows: windows, excludingPID: ownPID) {
                    let name = NSRunningApplication(processIdentifier: window.ownerPID)?.localizedName ?? "window"
                    overlay.setHighlight(window.bounds, readout: Readout(role: "window", identifier: nil, suffix: name, isFallback: false), around: point)
                } else {
                    overlay.setHighlight(nil, readout: .describing(nil), around: point)
                }
```

with

```swift
                lastHoverPoint = point
                let window = Geometry.windowOwner(at: point, windows: windows, excludingPID: ownPID)
                let drawn: Bool
                if let window {
                    let name = NSRunningApplication(processIdentifier: window.ownerPID)?.localizedName ?? "window"
                    drawn = overlay.setHighlight(window.bounds, readout: Readout(role: "window", identifier: nil, suffix: name, isFallback: false), around: point)
                } else {
                    drawn = overlay.setHighlight(nil, readout: .describing(nil), around: point)
                }
                if drawn, outlineMoves.moved(to: window?.bounds) { feedback?.tap(.alignment) }
```

- [ ] **Step 5: Point and Text: a new element taps; Option's step is its own tap.** Replace `renderHover()` (from `private func renderHover() {` through its closing brace) with

```swift
    /// v0.8.1 R59: a drawn outline that moved taps `.alignment`. Option's `step` taps `.levelChange`
    /// instead, and the move it causes is not also a tap.
    private func renderHover(step: Bool = false) {
        let element = selectedElement()
        var readout = Readout.describing(element)
        if levelIndex > 0 {
            readout.suffix = [readout.suffix, "↑\(levelIndex)"].compactMap { $0 }.joined(separator: " · ")
        }
        guard overlay.setHighlight(element?.frame.cgRect, readout: readout, around: lastHoverPoint) else { return }
        let moved = outlineMoves.moved(to: element?.frame.cgRect)
        if step {
            feedback?.tap(.levelChange)
        } else if moved {
            feedback?.tap(.alignment)
        }
    }
```

In `optionPressed()`, change its last line `renderHover()` to

```swift
        renderHover(step: true)
```

- [ ] **Step 6: A click holds the gate.** In `click(_:shift:)`, after `toast.hide()`:

```swift
        feedback?.clicked() // v0.8.1 R59: the trackpad just clicked; nothing taps for 80 ms
```

- [ ] **Step 7: Each session starts fresh.** In `reset()`, after `levelIndex = 0`:

```swift
        outlineMoves = OutlineMoves()
```

- [ ] **Step 8: The ring.** In `FloatingBall.pressBegan()`, after `self.ring.open(at: self.discCenter)`:

```swift
            self.feedback?.tap(.generic)
```

Replace `pressMoved(to:)` (from `func pressMoved(to point: CGPoint) {` through its closing brace) with

```swift
    /// v0.8.1 R59: every segment, and the center, is a detent.
    func pressMoved(to point: CGPoint) {
        guard ringOpen else { return }
        let before = ring.hovered
        if ring.hover(at: point, optionHeld: NSEvent.modifierFlags.contains(.option)) != before {
            feedback?.tap(.alignment)
        }
    }
```

`pressEnded(at:)` is unchanged: the release is a click, and a click never taps.

- [ ] **Step 9: Check that no click path taps.** The overlay's three taps go through `AppState.tapOutline`, which drops one while the trackpad's button is down (a lookup that started before the press must not tap after it). `grep -n "tapOutline\|feedback?.tap\|feedback?.clicked" Locant/App/AppState.swift Locant/Launcher/FloatingBall.swift` → eight lines: `tapOutline(.alignment)` in `drainHover`, `tapOutline`'s own declaration and the `feedback?.tap` inside it, `tapOutline(.levelChange)` and `tapOutline(.alignment)` in `renderHover`, `.clicked()` in `click`, `.generic` in `pressBegan`, `.alignment` in `pressMoved`. The ring's two keep calling `feedback?.tap` directly: it is used with the button held down. None in `pin`, `confirmSetIfAny`, `region`, `pressEnded`, `clicked`.
- [ ] **Step 10: Run all tests.** Expected: `** TEST SUCCEEDED **`; the warnings grep on that output prints nothing.
- [ ] **Step 11: Commit**

```bash
git add Locant/Capture/SelectionOverlay.swift Locant/App/AppState.swift Locant/Launcher/FloatingBall.swift
git commit -m "feedback: a tap when the drawn outline moves, when Option steps, when the ring opens and between its segments"
```

---

### Task 6: The sounds (R60)

**Files:**
- Modify: `Locant/App/AppState.swift` (`commit(note:)`, `finishOneShot`, its five callers in `runOneShot`, `beginColorPick()`, `fail(_:nearRect:)`)

**Interfaces:**
- Consumes: `Feedback.play(_:)`, `Feedback.Sound` (Task 4).
- Produces: `finishOneShot(_ text: NSAttributedString, near rect: CGRect, sound: Feedback.Sound)`.

- [ ] **Step 1: A Point capture lands.** In `commit(note:)`, between the `if let count = targets?.count { … } else { … }` toast block and the `// v0.8.1 R63` comment that precedes `if preferences.pastesIntoAgent`:

```swift
                feedback?.play(.landed)
```

- [ ] **Step 2: One-shots say which.** Replace `finishOneShot` (from `private func finishOneShot(` through its closing brace) with

```swift
    private func finishOneShot(_ text: NSAttributedString, near rect: CGRect, sound: Feedback.Sound) {
        reset()
        toast.show(text, near: rect)
        feedback?.play(sound) // v0.8.1 R60
    }
```

and give its five callers in `runOneShot` their sound:

```swift
                    finishOneShot(HudText.plain(optionHeld ? "Snapped · \(size) · clipboard only" : "Snapped · \(size)"), near: crop, sound: .landed)
```
```swift
                        finishOneShot(HudText.plain("No text found"), near: crop, sound: .missed)
```
```swift
                    finishOneShot(HudText.plain("Copied · \(lines.count) \(lines.count == 1 ? "line" : "lines")"), near: crop, sound: .landed)
```
```swift
                        finishOneShot(HudText.plain("No subject found"), near: crop, sound: .missed)
```
```swift
                    finishOneShot(HudText.plain(optionHeld ? "Cut · clipboard only" : "Cut"), near: crop, sound: .landed)
```

- [ ] **Step 3: A picked color lands.** In `beginColorPick()`, in `session.onPick`, after `toast.show(HudText.copied(identifier: text), near: CGRect(origin: cursor, size: .zero))`:

```swift
            feedback?.play(.landed)
```

- [ ] **Step 4: A failure is missed.** In `fail(_:nearRect:)`, after `toast.show(HudText.plain(error.message), near: rect)`:

```swift
        feedback?.play(.missed) // v0.8.1 R60
```

- [ ] **Step 5: Check the map.** `grep -n "feedback?.play\|PasteboardWriter.write\|toast.show\|finishOneShot(" Locant/App/AppState.swift`. Every `PasteboardWriter.write` is followed in its branch by `.landed` (commit, color pick) or sits in a `runOneShot` branch whose `finishOneShot` passes `.landed` (Snap, Text, Cut); `.missed` appears in `fail` and the two "No … found" calls. Silent by design: the toasts for "After #n", "No iterations yet", the hints, and the paste-into-the-agent outcome (R63: the capture already reached the clipboard and `landed` played); also silent, with no toast at all, a color-picker click before its first frame arrives and a capture that ends because `ContextCollector` returned nil.
- [ ] **Step 6: Run all tests.** Expected: `** TEST SUCCEEDED **`, no new warnings.
- [ ] **Step 7: Commit**

```bash
git add Locant/App/AppState.swift
git commit -m "feedback: landed when a capture reaches the clipboard, missed when nothing did"
```

---

### Task 7: Settings › General (R61)

**Files:**
- Modify: `Locant/App/SettingsView.swift` (`GeneralSettings`, a `Section` between the ball's and the updates')
- Modify: `Locant/App/AppState.swift` (`previewSound()`)

**Interfaces:**
- Consumes: `Preferences.trackpadTaps`, `Preferences.sounds` (Task 3), `AppState.feedback` (Task 4).
- Produces: `AppState.previewSound()`.

- [ ] **Step 1: The preview.** In `AppState`, insert immediately before the line `/// Settings › General "Locant Help": the same page, any time.` (the doc comment of `showHelp()`):

```swift
    /// v0.8.1 R61: turning Sounds on plays `landed` once, as Sound settings plays an alert.
    func previewSound() {
        feedback?.play(.landed)
    }

```

- [ ] **Step 2: The section.** In `GeneralSettings.body`, after the `Section` holding the "Floating ball" and "Auto-hide" toggles and before the `Section` holding "Check for updates":

```swift
            Section {
                Toggle(isOn: $preferences.trackpadTaps) {
                    Text("Trackpad taps")
                    Text("A light tap under your finger when the outline moves to a new element, when the ring opens, and between its segments. Needs a Force Touch trackpad.")
                }
                .toggleStyle(.switch)
                Toggle(isOn: $preferences.sounds) {
                    Text("Sounds")
                    Text("A soft sound when a capture reaches the clipboard, a lower one when nothing did. Follows Play user interface sound effects in Sound settings.")
                }
                .toggleStyle(.switch)
                .onChange(of: preferences.sounds) { _, on in
                    if on { state.previewSound() }
                }
            }
```

- [ ] **Step 3: Build and run all tests.** Expected: `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`, no new warnings.
- [ ] **Step 4: See it in both appearances.** Add a temporary `LocantTests/SettingsLookTests.swift` (delete it before committing; the group is file-system-synchronized, so no project edit). The window is 520 pt wide, the real Settings width:

```swift
import SwiftUI
import XCTest
@testable import Locant

@MainActor
final class SettingsLookTests: XCTestCase {
    func testCaptureGeneralSettings() async throws {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 520, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = NSHostingView(rootView: GeneralSettings().environment(AppState()))
            window.orderFrontRegardless()
            try await Task.sleep(for: .seconds(1))
            let out = ProcessInfo.processInfo.environment["SETTINGS_LOOK_DIR", default: NSTemporaryDirectory()]
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", "\(out)/settings-\(name).png"]
            try capture.run()
            capture.waitUntilExit()
            window.orderOut(nil)
        }
    }
}
```

Run `TEST_RUNNER_SETTINGS_LOOK_DIR="$SCRATCH" xcodebuild test -project Locant.xcodeproj -scheme Locant -derivedDataPath build/dd -only-testing:LocantTests/SettingsLookTests` (xcodebuild hands `TEST_RUNNER_`-prefixed variables to the test process without the prefix), open `$SCRATCH/settings-light.png` and `settings-dark.png`, and check: the section sits between the ball's and Check for updates; the copy is exactly as in Global Constraints and wraps cleanly at 520 pt; legible in both. Every switch draws a grey track because the window is not key; on is the knob at the right, and the state comes from the test host's real defaults, not the code default (PreferencesTests covers that). Then `rm LocantTests/SettingsLookTests.swift`.
- [ ] **Step 5: Commit**

```bash
git status --short   # SettingsLookTests.swift must not be listed
git add Locant/App/SettingsView.swift Locant/App/AppState.swift
git commit -m "settings: Trackpad taps and Sounds under the ball; turning Sounds on plays landed"
```

---

### Task 8: Ship the chosen set (R60; closes spec slot 1; needs Malik's pick)

Steps 3 and 5 need only the pick and can run as soon as Malik names a set; Steps 1, 2, 4 need `Feedback` (Task 4).

**Files:**
- Create: `Locant/Feedback/Sounds/landed.caf`, `Locant/Feedback/Sounds/missed.caf` (rendered, never hand-made)
- Create: `design/sound/README.md`
- Test: `LocantTests/FeedbackTests.swift`

**Interfaces:**
- Consumes: `design/sound/render ship <set>` (Task 1); `Feedback.Sound`, `Feedback.url(for:in:)`, `Feedback.playSound` (Task 4).

- [ ] **Step 1: Write the failing tests** (add `import AudioToolbox` under `import CoreGraphics` in `FeedbackTests.swift`, then append inside the class):

```swift
    // R60: both sounds ship: mono, 48 kHz, 24-bit, at most 250 ms, and they load as system sounds.
    func testSoundsShipShortAndLoadAsSystemSounds() throws {
        for sound in Feedback.Sound.allCases {
            let url = try XCTUnwrap(Feedback.url(for: sound, in: .main), "\(sound).caf is not in the app bundle")
            var fileID: AudioFileID?
            XCTAssertEqual(AudioFileOpenURL(url as CFURL, .readPermission, kAudioFileCAFType, &fileID), 0)
            let file = try XCTUnwrap(fileID)
            defer { AudioFileClose(file) }
            var duration: Float64 = 0
            var size = UInt32(MemoryLayout<Float64>.size)
            XCTAssertEqual(AudioFileGetProperty(file, kAudioFilePropertyEstimatedDuration, &size, &duration), 0)
            XCTAssertLessThanOrEqual(duration, 0.250, "\(sound) runs \(duration) s")
            var format = AudioStreamBasicDescription()
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            XCTAssertEqual(AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &format), 0)
            XCTAssertEqual(format.mSampleRate, 48_000)
            XCTAssertEqual(format.mChannelsPerFrame, 1)
            XCTAssertEqual(format.mBitsPerChannel, 24)
            var id: SystemSoundID = 0
            XCTAssertEqual(AudioServicesCreateSystemSoundID(url as CFURL, &id), kAudioServicesNoError)
            AudioServicesDisposeSystemSoundID(id)
        }
    }

    // R61: Sounds is read at the moment of each sound; landed and missed are two sounds.
    func testSoundsFollowTheSwitch() {
        let preferences = Preferences(defaults: isolatedDefaults())
        let feedback = Feedback(preferences: preferences)
        var played: [SystemSoundID] = []
        feedback.playSound = { played.append($0) }
        feedback.play(.landed)
        preferences.sounds = false
        feedback.play(.missed)
        preferences.sounds = true
        feedback.play(.missed)
        XCTAssertEqual(played.count, 2)
        XCTAssertNotEqual(played.first, played.last)
    }
```

- [ ] **Step 2: Run to see them fail.** One-class command. Expected: `testSoundsShipShortAndLoadAsSystemSounds` fails with "landed.caf is not in the app bundle" and `testSoundsFollowTheSwitch` with `XCTAssertEqual failed: ("0") is not equal to ("2")`.
- [ ] **Step 3: Render the chosen set** (`<set>` is Malik's pick: `glass`, `wood`, or `felt`):

```bash
swiftc -O design/sound/render.swift -o design/sound/render
design/sound/render ship <set>
afinfo Locant/Feedback/Sounds/landed.caf | grep -E "Data format|estimated duration"
afinfo Locant/Feedback/Sounds/missed.caf | grep -E "Data format|estimated duration"
```

Expected: two report lines from the script (`landed` and `missed`, 250 ms each, peaks −18.0 and −21.0 dBFS), and `afinfo` shows `1 ch, 48000 Hz, … 24-bit little-endian signed integer`, duration 0.25 for both.

- [ ] **Step 4: Run the tests.** Expected: 12 `FeedbackTests` pass; then all tests → `** TEST SUCCEEDED **`; `find build/dd/Build/Products/Debug/Locant.app -name "*.caf"` lists `Contents/Resources/landed.caf` and `missed.caf`.
- [ ] **Step 5: Write `design/sound/README.md`**, with `<Set>` and the two measurement lines filled from the `ship` output:

````markdown
# Locant sounds

`landed` plays when a capture reaches the clipboard, `missed` when nothing did (`specs/v0.8.1.md` R60).
Both are rendered by `render.swift`, never edited by hand; the shipped pair is in `Locant/Feedback/Sounds/`.

- Chosen Sep 19, 2026 by ear from three sets (Glass, Wood, Felt): **<Set>**.
- The figure is the same in every set: `landed` rises a fourth (E5 to A5), onsets 70 ms apart, the second
  struck 2 dB softer; `missed` is one C#5, its upper partials damped twice as fast, 3 dB quieter. Both last
  250 ms and fade to zero over the last 40 ms.
- Every parameter is in `sets` and the constants under it in `render.swift`. Change one, then:

```bash
swiftc -O design/sound/render.swift -o design/sound/render
design/sound/render candidates /tmp/locant-sounds   # every set as WAV, to listen
design/sound/render ship <set>                       # into Locant/Feedback/Sounds as CAF
```

Measured when shipped (the script's own report; macOS's Tink peaks at −8.8 dBFS and Pop at −11.1):

```
<the two lines printed by `render ship`>
```
````

- [ ] **Step 6: Commit**

```bash
git add Locant/Feedback/Sounds/landed.caf Locant/Feedback/Sounds/missed.caf design/sound/README.md LocantTests/FeedbackTests.swift
git commit -m "feedback: the <set> set ships as landed and missed"
```

---

### Task 9: Install, feel test, README (spec slot 3)

**Files:**
- Modify: `README.md` (the "What it does" table, a row after **Hotkeys**)
- Modify: `specs/v0.8.1.md` (a Status line)

- [ ] **Step 1: Everything green.** All tests → `** TEST SUCCEEDED **`; `git log --oneline origin/main..HEAD` shows only this branch's commits on top of main (which holds PR #38 and #37).
- [ ] **Step 2: Install over Malik's copy, keeping it.** Malik dogfoods paste into the agent from `/Applications/Locant.app`; this build contains it because the branch is on main.

```bash
ditto /Applications/Locant.app "$SCRATCH/Locant-before-taps.app"
osascript -e 'tell application id "com.malikzhang.deixis" to quit'
for i in $(seq 1 30); do pgrep -f "MacOS/Locant$" >/dev/null || break; sleep 0.5; done
if pgrep -f "MacOS/Locant$"; then echo "still running: stop and ask Malik"; exit 1; fi
rm -rf /Applications/Locant.app && ditto build/dd/Build/Products/Debug/Locant.app /Applications/Locant.app
codesign -dvv /Applications/Locant.app 2>&1 | grep -cE '^Authority=Developer ID Application: .*\(MVAUZXPK9M\)$|^TeamIdentifier=MVAUZXPK9M$'
diff <(codesign -d -r- "$SCRATCH/Locant-before-taps.app" 2>&1 | grep designated) <(codesign -d -r- /Applications/Locant.app 2>&1 | grep designated) && echo "same designated requirement"
open /Applications/Locant.app
```

Expected: the count prints `2` and `same designated requirement` prints (so the Accessibility and Screen Recording grants carry over); `pgrep -f "MacOS/Locant$"` shows one pid. If either check fails, restore the backup (`rm -rf /Applications/Locant.app && ditto "$SCRATCH/Locant-before-taps.app" /Applications/Locant.app`) and stop. Open Settings › General from the menu bar item: every row, the new section included, shows without scrolling (the window's one-time growth from 0.7.3).
- [ ] **Step 3: The feel test.** Hand Malik `specs/v0.8.1.md` §5 (seven steps) and wait. Nothing can observe a tap; never report taps as working until Malik has felt them. For each step that fails, write down the step and what Malik felt, fix it (a fix is its own commit with its own test run), re-install with Step 2, and have Malik repeat the failed steps before going on. If steps 1 and 3 give no taps with the switch on, stop and bring options: activating Locant would change how the app being pointed at looks.
- [ ] **Step 4: The README row** (R62), after the **Hotkeys** row of "What it does":

```markdown
| **Feedback** | A light trackpad tap when the outline moves to a new element, when the ring opens, and between its segments; a soft sound when a capture reaches the clipboard and a lower one when nothing did. The sounds follow the system's switch for interface sounds. Settings › General has a switch for each. |
```

```bash
git add README.md
git commit -m "readme: Feedback, taps under the finger and two sounds"
```

- [ ] **Step 5: Mark the spec built.** In `specs/v0.8.1.md`, add under the header lines `**Status:** R59–R62 built Sep <day>, 2026; feel test passed on Malik's MacBook Pro.` Commit `specs: v0.8.1 taps and sounds built`. The release (slot 4) waits for Malik and for both halves of 0.8.1 in main.
