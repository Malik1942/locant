# Trackpad taps and two sounds (v0.8.1 R59–R62) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A light trackpad tap when Locant's outline moves to a new element, when Option steps a level, when the ring opens and between its segments; a soft `landed` sound when a capture reaches the clipboard and a lower `missed` when nothing did; a switch for each in Settings › General.

**Architecture:** One `Feedback` object, owned by `AppState` like the toast and handed to the ball, wraps `NSHapticFeedbackManager` (taps) and AudioToolbox system sounds (two bundled CAF files made by `design/sound/render.swift`). Two pure structs decide when a tap may play: `TapGate` (at most one per 80 ms) and `OutlineMoves` (did the outline move). `AppState` and `FloatingBall` call `tap` and `play` at the moments the spec lists; `Preferences` holds the two switches.

**Tech Stack:** Swift 6 (strict concurrency `complete`), AppKit, SwiftUI, AudioToolbox (new, approved Sep 19, 2026), XCTest. macOS 15.0 deployment target.

## Global Constraints

- The spec is `specs/v0.8.1.md` (R59 taps, R60 sounds, R61 Settings, R62 sentences). Paste into the agent is R63 in `specs/v0.8.1-paste.md`: never edit that file, never add an R63 here.
- Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`, `MACOSX_DEPLOYMENT_TARGET = 15.0`: no `isolated deinit` (needs a newer runtime).
- Frameworks: Foundation, AppKit, SwiftUI, ScreenCaptureKit, Vision, ApplicationServices, and AudioToolbox. Only `Locant/Feedback/Feedback.swift` (and tests) import AudioToolbox. No third-party packages.
- One `@Observable` `AppState`, no other singletons: `Feedback` is created in `AppState.start()` and handed to the ball.
- Taps: `NSHapticFeedbackManager.defaultPerformer.perform(_:performanceTime: .drawCompleted)`; patterns `.alignment` (outline moves, ring segments), `.levelChange` (Option), `.generic` (ring opens); at most one per 80 ms (`DesignTokens.hover`); never on a click.
- Sounds: `landed`, `missed`; mono, 48 kHz, 24-bit linear PCM CAF, at most 250 ms; `landed` peaks at −18 dBFS ± 1 dB, `missed` 3 dB lower; played with `AudioServicesPlaySystemSoundWithCompletion`; `kAudioServicesPropertyIsUISound` left at its default.
- Settings copy, verbatim: "Trackpad taps" / "A light tap under your finger when the outline moves to a new element, when the ring opens, and between its segments. Needs a Force Touch trackpad." and "Sounds" / "A soft sound when a capture reaches the clipboard, a lower one when nothing did. Follows Play user interface sound effects in Sound settings."
- `docs/CLAUDE.md`: commit messages `area: what changed`, one intent each; never commit without a green build; match the surrounding comment density; doc comments cite the requirement (`v0.8.1 R59`); do not reformat untouched code; the README is written in the last slot.
- Build and test commands (from the worktree root; `build/` is git-ignored):
  - Build: `xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -derivedDataPath build/dd build 2>&1 | tail -3` → ends with `** BUILD SUCCEEDED **`
  - One test class: `xcodebuild test -project Locant.xcodeproj -scheme Locant -derivedDataPath build/dd -only-testing:LocantTests/FeedbackTests 2>&1 | grep -E "Test Case|error:|TEST (SUCCEEDED|FAILED)" | tail -20`
  - All tests: `xcodebuild test -project Locant.xcodeproj -scheme Locant -derivedDataPath build/dd 2>&1 | grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)" | tail -5`
- The test host is Locant itself, so `Bundle.main` in a test is the app bundle.
- `$SCRATCH` is a folder outside the repo for throwaway output (the session scratchpad); set it before the commands that use it.

## Prerequisite for Tasks 2 to 9: rebase onto main after PR #38

PR #38 (`am/mcp-operation-flow-4f5542`, paste into the agent) edits the same files: `AppState.swift` (`// MARK: Paste into the agent`, `commit(note:)` ends with `if preferences.pastesIntoAgent { await pasteIntoAgent(near:) } else { showAgentHintIfNeeded() }`), `Preferences.swift` (`pastesIntoAgent` after `checksForUpdates`), `PreferencesTests.swift` (`isolatedDefaults()` becomes an `XCTestCase` extension returning `InMemoryDefaults`). This plan's code is written against that state. Malik decides when #38 merges.

- [ ] Confirm it is merged: `gh pr view 38 --json state` → `"state":"MERGED"`. If not, stop; Task 1 is the only work allowed before it.
- [ ] `git fetch origin && git rebase origin/main` on `am/locant-touchpad-feedback-fa6821`. Expected: no conflicts (this branch holds only specs, `design/sound/render.swift`, one `.gitignore` line, and this plan).
- [ ] `grep -n "pastesIntoAgent\|func isolatedDefaults" Locant/Store/Preferences.swift LocantTests/PreferencesTests.swift` → both present.
- [ ] Build (command above) → `** BUILD SUCCEEDED **`.

---

### Task 1: The sound renderer and three candidate sets (spec slot 1)

**Status:** renderer committed as `41261d4`; candidates rendered and measured Sep 19, 2026. Remaining: Malik listens and picks a set.

**Files:**
- Create: `design/sound/render.swift` (done), `.gitignore` line `design/sound/render` (done)

**Interfaces:**
- Produces: `design/sound/render candidates <folder>` (WAV per set and sound) and `design/sound/render ship <glass|wood|felt>` (writes `Locant/Feedback/Sounds/landed.caf` and `missed.caf`, run from the repo root). Every parameter is in `sets` and the constants below it in `render.swift`.

- [x] **Step 1: Write `design/sound/render.swift`** (see the file: modal synthesis, SplitMix64 noise through RBJ biquads for the mallet, 2 ms raised-cosine attack, 40 ms raised-cosine fade to zero, peak normalization, 24-bit WAV writer, `afconvert` to CAF, a 16 384-point DFT for the band share).
- [x] **Step 2: Compile and render the candidates**

```bash
swiftc -O design/sound/render.swift -o design/sound/render
design/sound/render candidates "$SCRATCH/candidates"
```

Measured (script, cross-checked with `ffmpeg -af volumedetect`):

```
glass-landed  250 ms   peak  -18.0 dBFS   rms  -29.1 dBFS   500 Hz–5 kHz  99.9 %
glass-missed  200 ms   peak  -21.0 dBFS   rms  -32.9 dBFS   500 Hz–5 kHz  99.0 %
wood-landed   250 ms   peak  -18.0 dBFS   rms  -28.5 dBFS   500 Hz–5 kHz  99.9 %
wood-missed   200 ms   peak  -21.0 dBFS   rms  -32.1 dBFS   500 Hz–5 kHz  99.0 %
felt-landed   250 ms   peak  -18.0 dBFS   rms  -28.2 dBFS   500 Hz–5 kHz  99.9 %
felt-missed   200 ms   peak  -21.0 dBFS   rms  -31.0 dBFS   500 Hz–5 kHz  99.2 %
```

- [x] **Step 3: Commit** — `design: a sound renderer for landed and missed, three candidate sets` (`41261d4`).
- [ ] **Step 4: Audition.** Publish a private page with the six WAVs; Malik listens on speakers and headphones and names a set, or asks for changes (edit `sets`, re-render, republish). Task 8 needs the name.

---

### Task 2: `TapGate` and `OutlineMoves` (pure, R59)

**Files:**
- Create: `Locant/Feedback/TapGate.swift`
- Create: `LocantTests/FeedbackTests.swift`

**Interfaces:**
- Produces: `struct TapGate { var spacing: TimeInterval; mutating func admit(at now: TimeInterval) -> Bool }` (init `TapGate()`, spacing `DesignTokens.hover` = 0.080).
- Produces: `struct OutlineMoves { mutating func moved(to frame: CGRect?) -> Bool }` (init `OutlineMoves()`).

- [ ] **Step 1: Write the failing tests** in `LocantTests/FeedbackTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import Locant

@MainActor
final class FeedbackTests: XCTestCase {
    // v0.8.1 R59: one tap per 80 ms, measured from the last tap let through.
    func testTapGateSpacesTapsEightyMillisecondsApart() {
        var gate = TapGate()
        XCTAssertTrue(gate.admit(at: 10.000))
        XCTAssertFalse(gate.admit(at: 10.079))
        XCTAssertTrue(gate.admit(at: 10.080))
        XCTAssertFalse(gate.admit(at: 10.100))
    }

    // R59: a dropped tap does not restart the interval, so a steady sweep keeps its rhythm.
    func testTapGateDroppedTapsDoNotRestartTheInterval() {
        var gate = TapGate()
        XCTAssertTrue(gate.admit(at: 1.00))
        XCTAssertFalse(gate.admit(at: 1.05))
        XCTAssertTrue(gate.admit(at: 1.10), "100 ms after the last tap played, 50 ms after the dropped one")
    }

    // R59: hover redraws about every 33 ms; a sweep across small elements taps every third
    // redraw, evenly: a ratchet, not a buzz, not silence.
    func testTapGateAtHoverRateIsAnEvenRatchet() {
        var gate = TapGate()
        let played = (0..<30).map { Double($0) * 0.033 }.filter { gate.admit(at: $0) }
        XCTAssertEqual(played.count, 10)
        for (a, b) in zip(played, played.dropFirst()) {
            XCTAssertEqual(b - a, 0.099, accuracy: 0.0001)
        }
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
}
```

- [ ] **Step 2: Run them to see them fail.** One-class test command with `-only-testing:LocantTests/FeedbackTests`. Expected: build fails, `error: cannot find 'TapGate' in scope` and `cannot find 'OutlineMoves' in scope`.

- [ ] **Step 3: Write `Locant/Feedback/TapGate.swift`:**

```swift
import CoreGraphics
import Foundation

/// v0.8.1 R59: at most one tap per `spacing`, measured from the last tap let through. A dropped
/// tap neither restarts the interval nor plays later, so a fast sweep is an even ratchet.
struct TapGate {
    var spacing: TimeInterval = DesignTokens.hover
    private var last: TimeInterval?

    mutating func admit(at now: TimeInterval) -> Bool {
        if let last, now - last < spacing { return false }
        last = now
        return true
    }
}

/// v0.8.1 R59: whether the outline moved. The first outline after the overlay opens is not a
/// move, nor is one onto the no-element square (nil); leaving the square for an element is.
struct OutlineMoves {
    private var drawn = false
    private var last: CGRect?

    mutating func moved(to frame: CGRect?) -> Bool {
        defer { drawn = true; last = frame }
        guard drawn, let frame else { return false }
        return frame != last
    }
}
```

- [ ] **Step 4: Run the tests.** Same command. Expected: 5 tests pass, `** TEST SUCCEEDED **`.
- [ ] **Step 5: Commit**

```bash
git add Locant/Feedback/TapGate.swift LocantTests/FeedbackTests.swift
git commit -m "feedback: TapGate spaces taps 80 ms apart; OutlineMoves says when the outline moved"
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

- [ ] **Step 2: Run to see it fail.** `-only-testing:LocantTests/PreferencesTests`. Expected: `error: value of type 'Preferences' has no member 'trackpadTaps'`.

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

- [ ] **Step 4: Run the tests.** Same command. Expected: every `PreferencesTests` test passes.
- [ ] **Step 5: Commit**

```bash
git add Locant/Store/Preferences.swift LocantTests/PreferencesTests.swift
git commit -m "preferences: Trackpad taps and Sounds, both on by default"
```

---

### Task 4: `Feedback`, owned by `AppState` and handed to the ball (R59, R60, R62)

**Files:**
- Create: `Locant/Feedback/Feedback.swift`
- Modify: `Locant/App/AppState.swift` (a property beside `ball`; the first line of `start()`; `updateBall()`)
- Modify: `Locant/Launcher/FloatingBall.swift` (a property after `onAction`)
- Modify: `docs/CLAUDE.md:19`
- Test: `LocantTests/FeedbackTests.swift`

**Interfaces:**
- Consumes: `TapGate` (Task 2), `Preferences.trackpadTaps`, `Preferences.sounds` (Task 3).
- Produces: `@MainActor final class Feedback { enum Sound: String, CaseIterable, Sendable { case landed, missed }; init(preferences: Preferences, bundle: Bundle = .main); func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern); func play(_ sound: Sound); nonisolated static func url(for sound: Sound, in bundle: Bundle) -> URL? }`.
- Produces: `AppState.feedback: Feedback?` (private) and `FloatingBall.feedback: Feedback?`.

- [ ] **Step 1: Write the failing test** (append inside `FeedbackTests`):

```swift
    // R60: with no sound files (the test bundle has none) there is nothing to play, and playing
    // or tapping is a quiet no-op, not a crash.
    func testMissingSoundsAreSilent() {
        let bundle = Bundle(for: FeedbackTests.self)
        for sound in Feedback.Sound.allCases {
            XCTAssertNil(Feedback.url(for: sound, in: bundle))
        }
        let feedback = Feedback(preferences: Preferences(defaults: isolatedDefaults()), bundle: bundle)
        feedback.play(.landed)
        feedback.play(.missed)
        feedback.tap(.alignment)
    }
```

- [ ] **Step 2: Run to see it fail.** `-only-testing:LocantTests/FeedbackTests`. Expected: `error: cannot find 'Feedback' in scope`.

- [ ] **Step 3: Write `Locant/Feedback/Feedback.swift`:**

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

    private let preferences: Preferences
    private let soundIDs: [Sound: SystemSoundID]
    private var gate = TapGate()

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
        guard preferences.trackpadTaps, gate.admit(at: ProcessInfo.processInfo.systemUptime) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .drawCompleted)
    }

    /// R60: at once, with the toast. `kAudioServicesPropertyIsUISound` stays at its default, so
    /// the system keeps it silent while Play user interface sound effects is off.
    func play(_ sound: Sound) {
        guard preferences.sounds, let id = soundIDs[sound] else { return }
        AudioServicesPlaySystemSoundWithCompletion(id, nil)
    }

    /// The rendered file (`design/sound/render ship`); Xcode copies it flat into Resources.
    nonisolated static func url(for sound: Sound, in bundle: Bundle) -> URL? {
        bundle.url(forResource: sound.rawValue, withExtension: "caf")
    }
}
```

- [ ] **Step 4: Own it in `AppState` and hand it to the ball.** In `AppState`, after `@ObservationIgnored private var ball: FloatingBall?`:

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

- [ ] **Step 5: The framework line.** In `docs/CLAUDE.md` replace
`- No third-party packages. Foundation, AppKit, SwiftUI, ScreenCaptureKit, Vision, ApplicationServices only.`
with
`- No third-party packages. Foundation, AppKit, SwiftUI, ScreenCaptureKit, Vision, ApplicationServices, and AudioToolbox (the two interface sounds, specs/v0.8.1.md R60) only.`

- [ ] **Step 6: Run the tests.** `-only-testing:LocantTests/FeedbackTests` → 6 pass. Then the full build → `** BUILD SUCCEEDED **`, with no new warnings: `xcodebuild … build 2>&1 | grep -E "warning:.*(Feedback|TapGate)"` prints nothing.
- [ ] **Step 7: Commit**

```bash
git add Locant/Feedback/Feedback.swift Locant/App/AppState.swift Locant/Launcher/FloatingBall.swift LocantTests/FeedbackTests.swift docs/CLAUDE.md
git commit -m "feedback: taps and system sounds behind their switches, owned by AppState; AudioToolbox allowed"
```

---

### Task 5: The taps (R59)

**Files:**
- Modify: `Locant/App/AppState.swift` (`drainHover()` Snap/Cut branch, `renderHover()`, `optionPressed()`, `reset()`, a property)
- Modify: `Locant/Launcher/FloatingBall.swift` (`pressBegan()`, `pressMoved(to:)`)

**Interfaces:**
- Consumes: `OutlineMoves.moved(to:)` (Task 2), `Feedback.tap(_:)`, `AppState.feedback`, `FloatingBall.feedback` (Task 4), `Ring.hovered` and `Ring.hover(at:optionHeld:) -> Segment?` (existing).

- [ ] **Step 1: The property.** In `AppState`, after `@ObservationIgnored private var levelIndex = 0`:

```swift
    /// v0.8.1 R59: whether the outline moved since the last redraw; reset with each session.
    @ObservationIgnored private var outlineMoves = OutlineMoves()
```

- [ ] **Step 2: Snap and Cut: a new window under the cursor taps.** In `drainHover()`, replace

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
                if let window {
                    let name = NSRunningApplication(processIdentifier: window.ownerPID)?.localizedName ?? "window"
                    overlay.setHighlight(window.bounds, readout: Readout(role: "window", identifier: nil, suffix: name, isFallback: false), around: point)
                } else {
                    overlay.setHighlight(nil, readout: .describing(nil), around: point)
                }
                if outlineMoves.moved(to: window?.bounds) { feedback?.tap(.alignment) }
```

- [ ] **Step 3: Point and Text: a new element taps.** In `renderHover()`, after `overlay.setHighlight(element?.frame.cgRect, readout: readout, around: lastHoverPoint)`:

```swift
        if outlineMoves.moved(to: element?.frame.cgRect) { feedback?.tap(.alignment) }
```

- [ ] **Step 4: Option: the step is the tap.** Replace `optionPressed()` with

```swift
    /// Option while hovering: cluster, parent, grandparent, … then back to the element.
    /// v0.8.1 R59: the step is the tap; the frame change it causes is not also a move.
    private func optionPressed() {
        guard phase == .hovering, levels.count > 1 else { return }
        levelIndex = (levelIndex + 1) % levels.count
        feedback?.tap(.levelChange)
        _ = outlineMoves.moved(to: selectedElement()?.frame.cgRect)
        renderHover()
    }
```

- [ ] **Step 5: Each session starts fresh.** In `reset()`, after `levelIndex = 0`:

```swift
        outlineMoves = OutlineMoves()
```

- [ ] **Step 6: The ring.** In `FloatingBall.pressBegan()`, after `self.ring.open(at: self.discCenter)`:

```swift
            self.feedback?.tap(.generic)
```

Replace `pressMoved(to:)` with

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

- [ ] **Step 7: Check that no click path taps.** `grep -n "feedback?.tap" Locant/App/AppState.swift Locant/Launcher/FloatingBall.swift` → exactly five lines: `drainHover`, `renderHover`, `optionPressed`, `pressBegan`, `pressMoved`. None in `click`, `pin`, `confirmSetIfAny`, `region`, `pressEnded`, `clicked`.
- [ ] **Step 8: Run all tests** (all-tests command). Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 9: Commit**

```bash
git add Locant/App/AppState.swift Locant/Launcher/FloatingBall.swift
git commit -m "feedback: a tap when the outline moves, when Option steps, when the ring opens and between its segments"
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

- [ ] **Step 2: One-shots say which.** Replace `finishOneShot` with

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

- [ ] **Step 5: Check the map.** `grep -n "feedback?.play\|PasteboardWriter.write\|toast.show" Locant/App/AppState.swift`. Every `PasteboardWriter.write` is followed within its branch by `.landed` (commit, Snap, Text, Cut, Color); `.missed` appears in `fail` and the two "No … found" calls; the toasts for "After #n", "No iterations yet", and hints have no sound.
- [ ] **Step 6: Run all tests.** Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 7: Commit**

```bash
git add Locant/App/AppState.swift
git commit -m "feedback: landed when a capture reaches the clipboard, missed when nothing did"
```

---

### Task 7: Settings › General (R61)

**Files:**
- Modify: `Locant/App/SettingsView.swift` (`GeneralSettings`, a `Section` between the ball's and the updates')
- Modify: `Locant/App/AppState.swift` (`previewSound()`, beside `showHelp()`)

**Interfaces:**
- Consumes: `Preferences.trackpadTaps`, `Preferences.sounds` (Task 3), `AppState.feedback` (Task 4).
- Produces: `AppState.previewSound()`.

- [ ] **Step 1: The preview.** In `AppState`, before `func showHelp()`:

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

- [ ] **Step 3: Build and run all tests.** Expected: `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`.
- [ ] **Step 4: See it in both appearances.** Add a temporary `LocantTests/SettingsLookTests.swift` (delete it before committing; the group is file-system-synchronized, so no project edit):

```swift
import SwiftUI
import XCTest
@testable import Locant

@MainActor
final class SettingsLookTests: XCTestCase {
    func testCaptureGeneralSettings() async throws {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
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

Run `TEST_RUNNER_SETTINGS_LOOK_DIR="$SCRATCH" xcodebuild test -project Locant.xcodeproj -scheme Locant -derivedDataPath build/dd -only-testing:LocantTests/SettingsLookTests` (xcodebuild hands `TEST_RUNNER_`-prefixed variables to the test process without the prefix), open `$SCRATCH/settings-light.png` and `settings-dark.png`, and check: the section sits between the ball's and Check for updates, both switches on, the copy exactly as in Global Constraints, legible in both. Then `rm LocantTests/SettingsLookTests.swift`.
- [ ] **Step 5: Commit**

```bash
git status --short   # SettingsLookTests.swift must not be listed
git add Locant/App/SettingsView.swift Locant/App/AppState.swift
git commit -m "settings: Trackpad taps and Sounds under the ball; turning Sounds on plays landed"
```

---

### Task 8: Ship the chosen set (R60; needs Malik's pick from Task 1)

**Files:**
- Create: `Locant/Feedback/Sounds/landed.caf`, `Locant/Feedback/Sounds/missed.caf` (rendered, not hand-made)
- Create: `design/sound/README.md`
- Test: `LocantTests/FeedbackTests.swift`

**Interfaces:**
- Consumes: `design/sound/render ship <set>` (Task 1), `Feedback.Sound`, `Feedback.url(for:in:)` (Task 4).

- [ ] **Step 1: Write the failing test** (add `import AudioToolbox` at the top of `FeedbackTests.swift`, then append inside the class):

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
```

- [ ] **Step 2: Run to see it fail.** `-only-testing:LocantTests/FeedbackTests`. Expected: `testSoundsShipShortAndLoadAsSystemSounds` fails with "landed.caf is not in the app bundle".
- [ ] **Step 3: Render the chosen set** (`<set>` is Malik's pick: `glass`, `wood`, or `felt`):

```bash
swiftc -O design/sound/render.swift -o design/sound/render
design/sound/render ship <set>
afinfo Locant/Feedback/Sounds/landed.caf | grep -E "Data format|estimated duration"
```

Expected: two report lines from the script (`landed` 250 ms peak −18.0, `missed` 200 ms peak −21.0), and `afinfo` shows `1 ch, 48000 Hz, lpcm … 24-bit little-endian signed integer`, duration 0.25.

- [ ] **Step 4: Run the tests.** Expected: 7 `FeedbackTests` pass; then all tests → `** TEST SUCCEEDED **`; `find build/dd/Build/Products/Debug/Locant.app -name "*.caf"` lists `Contents/Resources/landed.caf` and `missed.caf`.
- [ ] **Step 5: Write `design/sound/README.md`**, with `<Set>` and the two measurement lines filled from the `ship` output:

````markdown
# Locant sounds

`landed` plays when a capture reaches the clipboard, `missed` when nothing did (`specs/v0.8.1.md` R60).
Both are rendered by `render.swift`, never edited by hand; the shipped pair is in `Locant/Feedback/Sounds/`.

- Chosen Sep 19, 2026 by ear from three sets (Glass, Wood, Felt): **<Set>**.
- The figure is the same in every set: `landed` rises a fourth (E5 to A5), onsets 70 ms apart, the second
  note 2 dB softer; `missed` is one C#5, its upper partials damped twice as fast, 3 dB quieter.
- Every parameter is in `sets` and the constants under it in `render.swift`. Change one, then:

```bash
swiftc -O design/sound/render.swift -o design/sound/render
design/sound/render candidates /tmp/locant-sounds   # every set as WAV, to listen
design/sound/render ship <set>                       # into Locant/Feedback/Sounds as CAF
```

Measured when shipped (the script's own report; Tink peaks at −8.8 dBFS and Pop at −11.1 for comparison):

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

- [ ] **Step 1: Everything green.** All tests → `** TEST SUCCEEDED **`; `git log --oneline origin/main..HEAD` shows only this plan's commits on top of main (which contains PR #38).
- [ ] **Step 2: Install over Malik's copy, keeping it.** Malik dogfoods paste into the agent from `/Applications/Locant.app`; this build contains it because the branch is on main after #38.

```bash
ditto /Applications/Locant.app "$SCRATCH/Locant-before-taps.app"
osascript -e 'tell application id "com.malikzhang.deixis" to quit'
for i in $(seq 1 30); do pgrep -f "MacOS/Locant$" >/dev/null || break; sleep 0.5; done
pgrep -f "MacOS/Locant$" && echo "still running: stop and ask" && exit 1
rm -rf /Applications/Locant.app && ditto build/dd/Build/Products/Debug/Locant.app /Applications/Locant.app
codesign -dv /Applications/Locant.app 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier=MVAUZXPK9M"
open /Applications/Locant.app
```

Expected: the signature lines print (so the Accessibility and Screen Recording grants carry over), and `pgrep -f "MacOS/Locant$"` shows one pid. Open Settings › General from the menu bar item: every row, the new section included, shows without scrolling (the window's one-time growth from 0.7.3).
- [ ] **Step 3: Hand Malik the feel test** (`specs/v0.8.1.md` §5, seven steps) and wait for the result. Nothing can observe a tap; do not report taps as working until Malik has felt them. If steps 1 and 3 give no taps with the switch on, stop and bring options: activating Locant would change how the app being pointed at looks.
- [ ] **Step 4: The README row** (R62), after the **Hotkeys** row of "What it does":

```markdown
| **Feedback** | A light trackpad tap when the outline moves to a new element, when the ring opens, and between its segments; a soft sound when a capture reaches the clipboard and a lower one when nothing did. The sounds follow the system's switch for interface sounds. Settings › General has a switch for each. |
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "readme: Feedback, taps under the finger and two sounds"
```

- [ ] **Step 6: Mark the spec built.** In `specs/v0.8.1.md`, add under the title's header lines `**Status:** R59–R62 built Sep <day>, 2026; feel test passed on Malik's MacBook Pro.` Commit `specs: v0.8.1 taps and sounds built`. The release (slot 4) waits for Malik and for both halves of 0.8.1 in main.
