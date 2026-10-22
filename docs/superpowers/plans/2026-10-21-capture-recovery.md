# Capture Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When replayd, the macOS process behind ScreenCaptureKit, lists no displays, Locant says so in an alert, restarts replayd in one click, and opens the failed action again (`specs/capture-recovery.md`, R109–R115).

**Architecture:** `ScreenCapture` gets one gateway, `shareableContent()`, that throws a new `ScreenCaptureFailure.serviceStuck` when ScreenCaptureKit lists no displays but CoreGraphics has some. `CaptureError.capturing(_:)` maps that to a new `.captureServiceStuck`, and everything else to `.captureFailed` as before. A new `CaptureRecovery` runs `/usr/bin/killall -9 replayd` and re-checks. `AppState.fail` shows the alert instead of the toast for that case, and Point watches its crops so the alert comes at the click, not at Enter. A Debug-only `StuckSimulation` fakes the stuck service for testing.

**Tech Stack:** Swift 6 (strict concurrency complete), AppKit (`NSAlert`, `NSRunningApplication`), ScreenCaptureKit, CoreGraphics (`CGGetActiveDisplayList`), Foundation (`Process`), XCTest. No packages, no new framework imports.

## Global Constraints

- **Errors:** typed enums, never strings (`docs/CLAUDE.md`).
- **Singletons:** one `@Observable` `AppState`, no other singletons. `StuckSimulation` is a Debug-only `@MainActor` namespace and is compiled out of Release.
- **No private API:** `killall` is a public tool, but replayd's name is not public API, so the code comments say so.
- **Clipboard:** never overwritten on a failed capture (R9, R111).
- **Copy, verbatim:**
  - "macOS screen capture stopped responding"
  - "Locant can restart it. Any screen recording or sharing in progress will stop."
  - "Restart Screen Capture"
  - "Not Now"
  - "Restarting screen capture…" (with the ellipsis character)
  - "Screen capture restarted"
  - "Screen capture still isn't responding"
  - "Restart your Mac to fix it."
  - "OK"
- **Re-check timing:** every 250 ms, for up to 3 s (R112). Focus wait: up to 1 s (R113).
- **Launch argument:** `-simulateStuckCapture once` or `-simulateStuckCapture always`, Debug builds only (R114).
- **Commits:** messages in the form `area: what changed`. Never commit without a green build (`docs/CLAUDE.md`). No attribution lines. Don't push.
- **Comments:** match the file's density and voice, and cite the requirement as `specs/capture-recovery.md R1xx` the first time in a file, then `R1xx`.
- **New files:** this repo's groups are file-system-synchronized, so new files need no `project.pbxproj` edit.

Shell setup used by every task (zsh):

```bash
cd /Users/malik/Documents/Locant/.claude/worktrees/locant-capture-access-issue-b7fa3e
SP=/private/tmp/claude-501/-Users-malik-Documents-Locant--claude-worktrees-locant-capture-access-issue-b7fa3e/9b14e718-66f3-4a67-b9a0-200aa01b4f4b/scratchpad
DD=$SP/dd
```

- **Build:** `xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet`. Expected: no output, exit 0.
- **Tests:** `xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' -derivedDataPath "$DD" test -quiet <-only-testing:…>`. Expected: exit 0. Without `-quiet`, the log ends with `** TEST SUCCEEDED **`.
- **zsh gotcha:** `log` is a zsh builtin. For the unified log, use `/usr/bin/log`.

Before Task 1, commit the spec and this plan on their own:

```bash
git add specs/capture-recovery.md docs/superpowers/plans/2026-10-21-capture-recovery.md
git commit -m "specs: fix stuck screen capture from inside the app"
```

---

### Task 1: Recognize the stuck service and say so (R109)

After this task, a stuck service toasts "macOS screen capture stopped responding" instead of "Capture failed". Task 3 turns that toast into the alert.

**Files:**
- Modify: `Locant/Capture/ScreenCapture.swift` (the failure enum, a new gateway, and the first lines of `displayImage` and `crop`)
- Modify: `Locant/Model/CaptureError.swift`
- Modify: `Locant/App/AppState.swift:1035`, `:1118`, and `fail` (`:1162-1171`)
- Create: `LocantTests/CaptureRecoveryTests.swift`

**Interfaces:**
- Produces:
  - `ScreenCaptureFailure.serviceStuck`
  - `static func ScreenCapture.isServiceStuck(captureDisplays: Int, activeDisplays: Int) -> Bool`
  - `static func ScreenCapture.activeDisplayCount() -> Int`
  - `private static func ScreenCapture.shareableContent() async throws -> SCShareableContent`
  - `CaptureError.captureServiceStuck`
  - `static func CaptureError.capturing(_ error: any Error) -> CaptureError`

- [ ] **Step 1: Write the failing tests.** Create `LocantTests/CaptureRecoveryTests.swift`:

```swift
import XCTest
@testable import Locant

/// specs/capture-recovery.md R109, R112: when the capture service counts as stuck, and what a
/// restart's re-check decides.
final class CaptureRecoveryTests: XCTestCase {
    // R109: stuck is no capture displays while CoreGraphics has at least one.
    func testStuckOnlyWhenCaptureListsNoDisplaysButTheMacHasSome() {
        XCTAssertTrue(ScreenCapture.isServiceStuck(captureDisplays: 0, activeDisplays: 1))
        XCTAssertTrue(ScreenCapture.isServiceStuck(captureDisplays: 0, activeDisplays: 3))
        XCTAssertFalse(ScreenCapture.isServiceStuck(captureDisplays: 0, activeDisplays: 0))
        XCTAssertFalse(ScreenCapture.isServiceStuck(captureDisplays: 1, activeDisplays: 1))
        XCTAssertFalse(ScreenCapture.isServiceStuck(captureDisplays: 3, activeDisplays: 3))
        XCTAssertFalse(ScreenCapture.isServiceStuck(captureDisplays: 1, activeDisplays: 0))
    }

    // R109: the stuck service keeps its own case; every other error is .captureFailed, as in R9.
    func testStuckServiceKeepsItsOwnCase() {
        guard case .captureServiceStuck = CaptureError.capturing(ScreenCaptureFailure.serviceStuck) else {
            return XCTFail("expected .captureServiceStuck")
        }
        guard case .captureFailed = CaptureError.capturing(ScreenCaptureFailure.noDisplay) else {
            return XCTFail("expected .captureFailed when the Mac has no display at all")
        }
        guard case .captureFailed = CaptureError.capturing(CocoaError(.fileWriteNoPermission)) else {
            return XCTFail("expected .captureFailed for a write error")
        }
    }

    func testStuckServiceMessage() {
        XCTAssertEqual(CaptureError.captureServiceStuck.message, "macOS screen capture stopped responding")
    }
}
```

- [ ] **Step 2: Run them to see them fail.** `xcodebuild … test -quiet -only-testing:LocantTests/CaptureRecoveryTests`. Expected: a build error, `type 'ScreenCapture' has no member 'isServiceStuck'`.

- [ ] **Step 3: Add the failure case and the pure test.** In `Locant/Capture/ScreenCapture.swift`, replace the failure enum:

```swift
enum ScreenCaptureFailure: Error {
    case noDisplay
    /// specs/capture-recovery.md R109: ScreenCaptureKit lists no displays while the Mac has some.
    case serviceStuck
    case cropOutsideImage
    case pngEncodingFailed
}
```

Inside `enum ScreenCapture`, after `requestPermission()`, add:

```swift
    /// R109: replayd, the process behind ScreenCaptureKit, can go stale (seen after a sleep and a
    /// monitor reconnect) and list windows but no displays, though the Mac has some.
    static func isServiceStuck(captureDisplays: Int, activeDisplays: Int) -> Bool {
        captureDisplays == 0 && activeDisplays > 0
    }

    /// CoreGraphics' count of active displays; needs no permission.
    static func activeDisplayCount() -> Int {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return 0 }
        return Int(count)
    }

    /// Every capture asks here first, so an empty display list always says why.
    private static func shareableContent() async throws -> SCShareableContent {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard content.displays.isEmpty else { return content }
        throw isServiceStuck(captureDisplays: 0, activeDisplays: activeDisplayCount())
            ? ScreenCaptureFailure.serviceStuck
            : ScreenCaptureFailure.noDisplay
    }
```

In both `displayImage(containing:)` and `crop(_:)`, replace the first line:

```swift
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
```

with:

```swift
        let content = try await shareableContent()
```

Keep each `guard let display = … else { throw ScreenCaptureFailure.noDisplay }` as it is; it still unwraps the display.

- [ ] **Step 4: Add the error case and the mapping.** Replace `Locant/Model/CaptureError.swift` with:

```swift
import Foundation

enum CaptureError: Error, Sendable {
    case noAccessibilityPermission
    case noScreenRecordingPermission
    case noElementUnderCursor
    case captureFailed(any Error)
    /// specs/capture-recovery.md R109: ScreenCaptureKit lists no displays while the Mac has some.
    case captureServiceStuck

    /// Short text for the 1-second toast.
    var message: String {
        switch self {
        case .noAccessibilityPermission: "Locant needs Accessibility access"
        case .noScreenRecordingPermission: "Locant needs Screen Recording access"
        case .noElementUnderCursor: "No accessibility element under the cursor"
        case .captureFailed: "Capture failed"
        case .captureServiceStuck: "macOS screen capture stopped responding"
        }
    }

    /// R109: what a capture threw, as the user hears it. Only the stuck service has its own case.
    static func capturing(_ error: any Error) -> CaptureError {
        if let failure = error as? ScreenCaptureFailure, failure == .serviceStuck { return .captureServiceStuck }
        return .captureFailed(error)
    }
}
```

- [ ] **Step 5: Route capture errors through the mapping.** In `Locant/App/AppState.swift`, in `runOneShot`'s catch (line 1035), replace:

```swift
                fail(.captureFailed(error), nearRect: crop)
```

with:

```swift
                fail(.capturing(error), nearRect: crop)
```

In `commit`'s catch (line 1118), replace:

```swift
                fail(.captureFailed(error), nearRect: anchor)
```

with:

```swift
                fail(.capturing(error), nearRect: anchor)
```

In `fail`, replace:

```swift
        case .noElementUnderCursor, .captureFailed: break
```

with:

```swift
        case .noElementUnderCursor, .captureFailed, .captureServiceStuck: break
```

- [ ] **Step 6: Run the tests.** `xcodebuild … test -quiet -only-testing:LocantTests/CaptureRecoveryTests`. Expected: exit 0.

- [ ] **Step 7: Run all tests and build.** `xcodebuild … test -quiet`, then the build command. Expected: both exit 0.

- [ ] **Step 8: Commit.**

```bash
git add Locant/Capture/ScreenCapture.swift Locant/Model/CaptureError.swift Locant/App/AppState.swift LocantTests/CaptureRecoveryTests.swift
git commit -m "capture: name a stuck screen capture service instead of Capture failed"
```

---

### Task 2: Restart replayd and re-check, with a Debug switch (R112, R114)

**Files:**
- Create: `Locant/Capture/CaptureRecovery.swift`
- Modify: `Locant/Capture/ScreenCapture.swift` (add `capturableDisplayCount()` and `StuckSimulation`; the simulation check at the top of `shareableContent()`)
- Test: `LocantTests/CaptureRecoveryTests.swift`

**Interfaces:**
- Consumes: `ScreenCaptureFailure.serviceStuck` and `ScreenCapture.shareableContent()` (Task 1)
- Produces:
  - `enum CaptureRecovery.Outcome: Equatable, Sendable { case recovered, restartMac }`
  - `static func CaptureRecovery.outcome(displaysAfter: Int) -> CaptureRecovery.Outcome`
  - `static func CaptureRecovery.restart() async -> CaptureRecovery.Outcome`
  - `static func ScreenCapture.capturableDisplayCount() async -> Int`
  - In Debug only: `@MainActor enum StuckSimulation` with `static var isActive: Bool` and `static func noteRestart()`

- [ ] **Step 1: Write the failing tests.** Append inside `CaptureRecoveryTests`, before the closing brace:

```swift
    // R112: recovered once ScreenCaptureKit lists a display again.
    func testOutcomeAfterTheRecheck() {
        XCTAssertEqual(CaptureRecovery.outcome(displaysAfter: 1), .recovered)
        XCTAssertEqual(CaptureRecovery.outcome(displaysAfter: 3), .recovered)
        XCTAssertEqual(CaptureRecovery.outcome(displaysAfter: 0), .restartMac)
    }

    // R114: without the launch argument, nothing is simulated.
    @MainActor
    func testSimulationIsOffWithoutTheLaunchArgument() {
        XCTAssertFalse(StuckSimulation.isActive)
    }
```

Never call `CaptureRecovery.restart()` from a test: it kills the real replayd.

- [ ] **Step 2: Run them to see them fail.** `xcodebuild … test -quiet -only-testing:LocantTests/CaptureRecoveryTests`. Expected: a build error, `cannot find 'CaptureRecovery' in scope`.

- [ ] **Step 3: Add the simulation and the display count.** In `Locant/Capture/ScreenCapture.swift`, make `shareableContent()` start with the simulation check:

```swift
    /// Every capture asks here first, so an empty display list always says why.
    private static func shareableContent() async throws -> SCShareableContent {
        #if DEBUG
        if await StuckSimulation.isActive { throw ScreenCaptureFailure.serviceStuck }
        #endif
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard content.displays.isEmpty else { return content }
        throw isServiceStuck(captureDisplays: 0, activeDisplays: activeDisplayCount())
            ? ScreenCaptureFailure.serviceStuck
            : ScreenCaptureFailure.noDisplay
    }

    /// R112: how many displays ScreenCaptureKit lists now; 0 when it lists none or fails.
    static func capturableDisplayCount() async -> Int {
        (try? await shareableContent().displays.count) ?? 0
    }
```

At the end of the file, after the closing brace of `enum ScreenCapture`, add:

```swift
#if DEBUG
/// specs/capture-recovery.md R114: `-simulateStuckCapture once|always` makes every capture throw
/// `.serviceStuck` without asking ScreenCaptureKit. `once` ends at the first restart (R112);
/// `always` lasts until quit. Debug builds only.
@MainActor
enum StuckSimulation {
    private static let mode = UserDefaults.standard.string(forKey: "simulateStuckCapture")
    private static var restarted = false

    static var isActive: Bool {
        switch mode {
        case "always": true
        case "once": !restarted
        default: false
        }
    }

    static func noteRestart() { restarted = true }
}
#endif
```

- [ ] **Step 4: Add the restart.** Create `Locant/Capture/CaptureRecovery.swift`:

```swift
import Foundation

/// specs/capture-recovery.md R112: restart replayd, the process behind ScreenCaptureKit, when it
/// lists no displays, then ask again until displays come back. replayd's name is not public API;
/// if Apple renames it, `killall` finds nothing, the re-check stays empty, and the user is told to
/// restart the Mac (R113).
enum CaptureRecovery {
    enum Outcome: Equatable, Sendable {
        case recovered, restartMac
    }

    static let recheckInterval: Duration = .milliseconds(250)
    static let recheckLimit: Duration = .seconds(3)

    static func outcome(displaysAfter: Int) -> Outcome {
        displaysAfter > 0 ? .recovered : .restartMac
    }

    /// Kills replayd, then asks ScreenCaptureKit every `recheckInterval` for up to `recheckLimit`.
    /// The asking is what makes launchd start a new replayd.
    static func restart() async -> Outcome {
        await killReplayd()
        #if DEBUG
        await StuckSimulation.noteRestart()
        #endif
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: recheckLimit)
        var displays = await ScreenCapture.capturableDisplayCount()
        while outcome(displaysAfter: displays) == .restartMac, clock.now < deadline {
            try? await Task.sleep(for: recheckInterval)
            displays = await ScreenCapture.capturableDisplayCount()
        }
        return outcome(displaysAfter: displays)
    }

    /// The signal comes from `killall`, an Apple binary running as the user, so Locant needs no
    /// entitlement and its hardened runtime does not apply. SIGKILL, because a hung replayd ignored
    /// SIGTERM. The exit status is not read: the re-check is the answer.
    private static func killReplayd() async {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/killall")
            process.arguments = ["-9", "replayd"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            process.waitUntilExit()
        }.value
    }
}
```

- [ ] **Step 5: Run the tests.** `xcodebuild … test -quiet -only-testing:LocantTests/CaptureRecoveryTests`. Expected: exit 0.

- [ ] **Step 6: Confirm Release has no simulation.** `xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Release -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet CODE_SIGNING_ALLOWED=NO`. Expected: exit 0. Then run `strings "$DD/Build/Products/Release/Locant.app/Contents/MacOS/Locant" | grep -c simulateStuckCapture`. Expected: `0`.

- [ ] **Step 7: Run all tests and the Debug build.** `xcodebuild … test -quiet`, then the build command. Expected: both exit 0.

- [ ] **Step 8: Commit.**

```bash
git add Locant/Capture/CaptureRecovery.swift Locant/Capture/ScreenCapture.swift LocantTests/CaptureRecoveryTests.swift
git commit -m "capture: restart replayd and re-check, with a Debug switch to simulate it stuck"
```

---

### Task 3: The alert, Point at the click, and after the restart (R110, R111, R113, R115)

`AppState` is UI and has no unit tests (`docs/CLAUDE.md`). Task 4 checks this task in the app.

**Files:**
- Modify: `Locant/App/AppState.swift`: three crop sites (`:892`, `:916-917`, `:968`), `fail` (`:1162-1171`), and three new private methods after `fail`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `CaptureError.captureServiceStuck` and `CaptureError.capturing(_:)` (Task 1); `CaptureRecovery.restart()`, `CaptureRecovery.Outcome` (Task 2); and the existing `beginAction(_:)`, `inform(_:detail:)`, `toast`, `feedback`, `context?.frontPID`, `ownPID`, `clickPoint`, `cropTask`, `extraCropTasks`, `phase`, `SelectionOverlay.fallbackRect(around:)`.
- Produces: `private func watchForStuckCapture()`, `private func offerCaptureRestart(retrying:sourcePID:near:)`, `private func returnFocus(to:) async`.

- [ ] **Step 1: Show the alert from `fail`.** Replace the whole `fail` function:

```swift
    private func fail(_ error: CaptureError, nearRect anchor: CGRect?) {
        reset()
        let rect = anchor ?? Self.mainScreenCenterCG()
        toast.show(HudText.plain(error.message), near: rect)
        feedback?.play(.missed) // v0.8.1 R60
        switch error {
        case .noAccessibilityPermission: openSettingsOnce(pane: "Privacy_Accessibility")
        case .noScreenRecordingPermission: openSettingsOnce(pane: "Privacy_ScreenCapture")
        case .noElementUnderCursor, .captureFailed, .captureServiceStuck: break
        }
    }
```

with:

```swift
    private func fail(_ error: CaptureError, nearRect anchor: CGRect?) {
        // specs/capture-recovery.md R113: what to begin again after a restart, read before reset clears it.
        let failedAction = action
        let sourcePID = context?.frontPID
        reset()
        let rect = anchor ?? Self.mainScreenCenterCG()
        if case .captureServiceStuck = error {
            feedback?.play(.missed) // v0.8.1 R60
            offerCaptureRestart(retrying: failedAction, sourcePID: sourcePID, near: rect)
            return
        }
        toast.show(HudText.plain(error.message), near: rect)
        feedback?.play(.missed) // v0.8.1 R60
        switch error {
        case .noAccessibilityPermission: openSettingsOnce(pane: "Privacy_Accessibility")
        case .noScreenRecordingPermission: openSettingsOnce(pane: "Privacy_ScreenCapture")
        case .noElementUnderCursor, .captureFailed, .captureServiceStuck: break
        }
    }

    /// R111–R113: the alert, the restart, and the same action again once displays are back.
    private func offerCaptureRestart(retrying failed: Action, sourcePID: pid_t?, near rect: CGRect) {
        let alert = NSAlert()
        alert.messageText = "macOS screen capture stopped responding"
        alert.informativeText = "Locant can restart it. Any screen recording or sharing in progress will stop."
        alert.addButton(withTitle: "Restart Screen Capture")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Up past the 3 s re-check (R112); taken down as soon as it ends.
        toast.show(HudText.plain("Restarting screen capture…"), near: rect, life: 5)
        Task {
            let outcome = await CaptureRecovery.restart()
            toast.hide()
            guard outcome == .recovered else {
                inform("Screen capture still isn't responding", detail: "Restart your Mac to fix it.")
                return
            }
            await returnFocus(to: sourcePID)
            toast.show(HudText.plain("Screen capture restarted"), near: rect)
            beginAction(failed)
        }
    }

    /// R113: `ContextCollector.collect` takes the frontmost app as the source, which after the alert
    /// is Locant. Hand focus back to the app the capture began over and wait up to a second for it.
    private func returnFocus(to pid: pid_t?) async {
        guard let pid, pid != ownPID, let app = NSRunningApplication(processIdentifier: pid) else { return }
        _ = app.activate(options: [])
        var waited = 0
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != pid, waited < 20 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
    }
```

- [ ] **Step 2: Stop Point at the click.** Under `// MARK: Failure (R9)`, directly above `fail`, add:

```swift
    /// specs/capture-recovery.md R110: Point's crops run at the click. A stuck capture service stops
    /// the session then, before the note is typed, instead of at Enter. Other failures still wait
    /// for Enter (R9); a session that ended or moved on is left alone.
    private func watchForStuckCapture() {
        let tasks = [cropTask].compactMap { $0 } + extraCropTasks
        guard let first = tasks.first else { return }
        let anchor = SelectionOverlay.fallbackRect(around: clickPoint)
        Task {
            for task in tasks {
                guard case .failure(let error) = await task.result,
                      case .captureServiceStuck = CaptureError.capturing(error) else { continue }
                guard phase == .noting, cropTask == first else { return }
                fail(.captureServiceStuck, nearRect: anchor)
                return
            }
        }
    }
```

Then call it at each of Point's three crop sites. In the click path, replace:

```swift
            cropTask = Task { try await ScreenCapture.crop(rect) }
```

with:

```swift
            cropTask = Task { try await ScreenCapture.crop(rect) }
            watchForStuckCapture()
```

In `finishSet`, replace:

```swift
        extraCropTasks = rects.dropFirst().map { rect in Task { try await ScreenCapture.crop(rect) } }
```

with:

```swift
        extraCropTasks = rects.dropFirst().map { rect in Task { try await ScreenCapture.crop(rect) } }
        watchForStuckCapture()
```

In the drawn-frame path, replace:

```swift
            cropTask = Task { try await ScreenCapture.crop(crop) }
```

with:

```swift
            cropTask = Task { try await ScreenCapture.crop(crop) }
            watchForStuckCapture()
```

Each site sets `phase = .noting` a few lines later, in the same synchronous run. The watcher's `Task` inherits the main actor, so its first check sees `.noting`.

- [ ] **Step 3: Build.** Run the build command. Expected: exit 0. If Swift 6 complains about `cropTask == first`, check that `Task` is `Equatable`, which it is. Do not add `@unchecked` anything.

- [ ] **Step 4: CHANGELOG (R115).** In `CHANGELOG.md`, insert this between the intro paragraph and `## 1.0.0 (2026-10-19)`:

```markdown
## Unreleased

- **Stuck screen capture is fixed from Locant.** When the macOS process behind screen capture stops answering, every capture used to say "Capture failed", even after relaunching Locant. Now Locant says what is wrong, offers Restart Screen Capture, and opens the same action again. Point stops right at the click instead of after you type the note.

```

- [ ] **Step 5: Run all tests and build.** `xcodebuild … test -quiet`, then the build command. Expected: both exit 0.

- [ ] **Step 6: Commit.**

```bash
git add Locant/App/AppState.swift CHANGELOG.md
git commit -m "capture: offer to restart stuck screen capture, then open the action again"
```

---

### Task 4: Check it in the app (spec §3)

This task needs Malik's hands for the clicks: synthetic input is unreliable while he is at the Mac. Ask him first, then do the setup, then walk him through each run and check the results from the shell. A step that fails goes back to its task. Don't patch here.

**Files:** none. Commit only if a fix was needed, in its own commit.

- [ ] **Step 1: Set up.**

```bash
defaults export com.malikzhang.deixis "$SP/defaults-before.plist"
osascript -e 'tell application id "com.malikzhang.deixis" to quit'
for i in $(seq 1 30); do pgrep -f "MacOS/Locant$" >/dev/null || break; perl -e 'sleep 0.5'; done
pgrep -f "MacOS/Locant$" && echo "still running: stop and ask Malik"
mkdir -p "$SP/captures"
APP="$DD/Build/Products/Debug/Locant.app"
launch() { open -n "$APP" --args -simulateStuckCapture "$1" -pastesIntoAgent '<false/>' -checksForUpdates '<false/>' -collectsIterations '<false/>' -ballEnabled '<false/>' -captureFolder "$SP/captures"; }
stop() { pkill -f "Debug/Locant.app/Contents/MacOS/Locant -simulateStuckCapture"; perl -e 'sleep 2'; }
replayd() { pgrep -x replayd || echo none; }
clip() { pbpaste | shasum | cut -c1-12; osascript -e 'clipboard info' | head -c 120; echo; }
```

- [ ] **Step 2: Point, then Restart.** `launch once`, then record `replayd` and `clip`. Ask Malik to double-tap ⌃ over an app other than Locant (Dia, say) and click a button.
  - **Expect:** the alert, before he can type; no overlay or note field left behind; `ls "$SP/captures"` is empty; `clip` is unchanged.
  - **Then:** he clicks Restart Screen Capture. Expect "Restarting screen capture…", then "Screen capture restarted", and Point open over Dia. `replayd` prints a new PID.
  - **Then:** he points, types "test", and presses Return. Expect one PNG and one JSON in `$SP/captures`. `plutil -extract source.app.name raw "$SP"/captures/*.json` prints the target app's name (not "Locant"), and `clip` has changed.

- [ ] **Step 3: Snap.** `stop; launch once`. Ask Malik to pick Snap from the Locant menu bar menu and click a window.
  - **Expect:** the alert.
  - **Then:** Restart. Expect Snap open again. A click puts an image on the clipboard: `osascript -e 'clipboard info'` lists `«class PNGf»`.

- [ ] **Step 4: Not Now.** `stop; launch once`. Point once, then Not Now.
  - **Expect:** no new file, `clip` unchanged.
  - **Then:** Point again. Expect the alert again.

- [ ] **Step 5: Still stuck, and Color.** `stop; launch always`. Point, then Restart.
  - **Expect:** "Screen capture still isn't responding" / "Restart your Mac to fix it." with only OK.
  - **Then:** Malik picks Color from the menu and moves over the screen. Expect no alert; the magnifier may stay empty.
  - **Verify:** not runnable here (collecting is off). Confirm by reading that its catch in `AppState` (`// Silent (R52)`) never calls `fail`.

- [ ] **Step 6: Restore.**

```bash
stop
defaults export com.malikzhang.deixis "$SP/defaults-after.plist"
diff <(plutil -p "$SP/defaults-before.plist") <(plutil -p "$SP/defaults-after.plist")
open -a /Applications/Locant.app
```

  For each key the diff shows as changed, write Malik's old value back (`defaults write com.malikzhang.deixis <key> …`, or `defaults delete` for an added key), using the XML form for arrays (see memory note on `ballPosition`). Confirm `pgrep -f "MacOS/Locant$"` shows one PID from `/Applications`.

- [ ] **Step 7: Report.** In three lines: what passed, what was skipped (Verify ran only as a code read), and what is unsure.
