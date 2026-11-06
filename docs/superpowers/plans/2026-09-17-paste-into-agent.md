# Paste Into the Agent After Return — Implementation Plan

> **Sep 19, 2026: renumbered to v0.8.1 R63** (`specs/v0.8.1.md` holds R59–R62 for taps and sounds). **Sending was removed after the first dogfood.** Locant pastes and never presses Return; the "Send when there is a note" switch, `AgentPaste.sends`, `Outcome.sent`, and `AgentPaster.sendGap` are gone. Tasks 1–5 below record what was built on Sep 17 and still mention them. `specs/v0.8.1-paste.md` R63 ("Never sends") is authoritative; Task 6 is updated to its five checks.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `specs/v0.8.1-paste.md` R63: an opt-in option (off by default) that, after Return on a Point capture, brings the agent app the user used last forward and pastes the capture into it, pressing Return too when there is a note and a second switch is on.

**Architecture:** One new file, `Locant/Payload/AgentPaste.swift`, split the way the repo splits `AgentConfig` (pure, tested) from `AgentConnector` (impure, untested): `AgentPaste` holds every decision as pure functions; `AgentPaster` activates the app and posts the keys. `AppState` records the last agent from an activation observer of its own and calls the paster at the end of `commit(note:)`, after the clipboard is written. The clipboard, the files, and the MCP server are unchanged.

**Tech Stack:** Swift 6.0 (strict concurrency `complete`), macOS 15.0, AppKit, SwiftUI, ApplicationServices (AX, CGEvent), Carbon.HIToolbox (already imported by `Locant/Capture/HotkeyConflicts.swift`; used here for key codes and `UCKeyTranslate`), XCTest.

## Global Constraints

- The spec is `specs/v0.8.1-paste.md` R63. If this plan and the spec disagree, the spec wins; say so and continue.
- House rules are `CLAUDE.md`: pure functions get tests; accessibility calls run on the `AccessibilityReader` actor; no third-party packages; no private API; never overwrite the clipboard on a failed capture.
- Both new preferences default to `false`: `pastesIntoAgent`, `sendsWithNote`.
- Agent apps are matched by exact bundle id, never by name: `com.anthropic.claudefordesktop`, `com.todesktop.230313mzl4w4u92`, `com.openai.codex`.
- No new permission. Posting keys rides on the Accessibility grant Locant already requires.
- The clipboard item written by `PasteboardWriter` is pasted as-is. Nothing is saved or restored.
- Point captures only (`commit(note:)`). Snap, Text, Color, Cut are untouched.
- Settings copy, verbatim:
  - `Paste into your agent` / "After Return, Locant brings forward the agent app you used last, Claude, Cursor, or Codex, and pastes the capture there."
  - `Send when there is a note` / "Locant also presses Return in the agent. Without a note, the capture waits in the message field."
  - Footnote: "The note field shows where the capture will go. The clipboard holds it either way, and connected agents can still fetch it."
- Toasts, verbatim: `Copied · no agent yet`, `Copied · <app> didn't come forward`, `Copied · pasting needs Accessibility`.
- Commits: one intent each, `area: what changed`, never without a green build, no attribution lines.
- New `.swift` files under `Locant/` and `LocantTests/` join their targets automatically (the project uses file-system synchronized groups); do not edit `project.pbxproj`.

**Commands used throughout** (run from the repo root):

```bash
# one test class
xcodebuild test -scheme Locant -destination 'platform=macOS' -only-testing:LocantTests/<Class> 2>&1 | grep -E "error:|Executed|\*\* TEST"
# build only
xcodebuild build -scheme Locant -destination 'platform=macOS' 2>&1 | grep -E "error:|\*\* BUILD"
# everything
xcodebuild test -scheme Locant -destination 'platform=macOS' 2>&1 | grep -E "error:|Executed [0-9]+ tests|\*\* TEST" | tail -3
```

**One deliberate reading of the spec:** the spec's "wait 150 ms (the overlay orders out about 140 ms after `reset()`)" is done in two places here. `AppState.pasteIntoAgent` waits `DesignTokens.dismiss` + 40 ms before activating, so no Locant panel is key when the agent comes forward; `AgentPaster` then waits 150 ms after the agent is frontmost, so Electron can put focus back in its composer. Both are dogfood-tunable constants.

---

### Task 1: The pure decisions (`AgentPaste`)

**Files:**
- Create: `Locant/Payload/AgentPaste.swift`
- Test: `LocantTests/AgentPasteTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (used by Tasks 3, 4, 5):
  - `enum AgentPaste` (nonisolated; the project sets no default actor isolation)
  - `static let bundleIds: Set<String>`
  - `static func isAgent(bundleId: String?) -> Bool`
  - `static func sends(note: String, enabled: Bool) -> Bool`
  - `struct TargetLabel: Equatable, Sendable { var lead: String; var title: String? }`
  - `static func label(appName: String?, windowTitle: String?) -> TargetLabel`
  - `enum Outcome: Equatable, Sendable { case pasted, sent, noAgent, noPermission, didNotComeForward }`
  - `static func toastText(_ outcome: Outcome, appName: String?) -> String?`
  - `static let eventMarker: Int64`
  - `static func isOwnEvent(userData: Int64) -> Bool`

- [ ] **Step 1: Write the failing test**

Create `LocantTests/AgentPasteTests.swift`:

```swift
import XCTest
@testable import Locant

final class AgentPasteTests: XCTestCase {
    // 1: exact bundle ids; a shared word is not enough.
    func testOnlyTheThreeAgentAppsCount() {
        XCTAssertTrue(AgentPaste.isAgent(bundleId: "com.anthropic.claudefordesktop"))
        XCTAssertTrue(AgentPaste.isAgent(bundleId: "com.todesktop.230313mzl4w4u92"))
        XCTAssertTrue(AgentPaste.isAgent(bundleId: "com.openai.codex"))
        for other in [
            "com.openai.chat", "com.steipete.codexbar", "com.anthropic.claude-code",
            "com.anthropic.claude-code-url-handler", "com.anthropic.claudefordesktop.helper",
            "com.openai.codex.helper", "com.apple.Terminal",
        ] {
            XCTAssertFalse(AgentPaste.isAgent(bundleId: other), other)
        }
        XCTAssertFalse(AgentPaste.isAgent(bundleId: nil))
    }

    // 2: Return goes to the agent only for a note with words in it, and only with the switch on.
    func testSendsOnlyANoteWithTheSwitchOn() {
        XCTAssertTrue(AgentPaste.sends(note: "make it rounded", enabled: true))
        XCTAssertFalse(AgentPaste.sends(note: "make it rounded", enabled: false))
        XCTAssertFalse(AgentPaste.sends(note: "", enabled: true))
        XCTAssertFalse(AgentPaste.sends(note: "  \n\t ", enabled: true))
    }

    // 3: the label names the app at once and the window when it is known.
    func testLabelNamesTheAppThenTheWindow() {
        XCTAssertEqual(AgentPaste.label(appName: nil, windowTitle: "x"), .init(lead: "→ no agent yet", title: nil))
        XCTAssertEqual(AgentPaste.label(appName: "Cursor", windowTitle: nil), .init(lead: "→ Cursor", title: nil))
        XCTAssertEqual(AgentPaste.label(appName: "Cursor", windowTitle: "   "), .init(lead: "→ Cursor", title: nil))
        XCTAssertEqual(AgentPaste.label(appName: "ChatGPT", windowTitle: " Deixis — v0.9 "), .init(lead: "→ ChatGPT", title: "Deixis — v0.9"))
    }

    // 4: the toast speaks only when nothing was pasted.
    func testToastExplainsOnlyAMissedPaste() {
        XCTAssertNil(AgentPaste.toastText(.pasted, appName: "Cursor"))
        XCTAssertNil(AgentPaste.toastText(.sent, appName: "Cursor"))
        XCTAssertEqual(AgentPaste.toastText(.noAgent, appName: nil), "Copied · no agent yet")
        XCTAssertEqual(AgentPaste.toastText(.didNotComeForward, appName: "Cursor"), "Copied · Cursor didn't come forward")
        XCTAssertEqual(AgentPaste.toastText(.didNotComeForward, appName: nil), "Copied · the agent didn't come forward")
        XCTAssertEqual(AgentPaste.toastText(.noPermission, appName: "Cursor"), "Copied · pasting needs Accessibility")
    }

    // 5: Locant's own posted keys are known by their marker, and nothing else is.
    func testOwnEventsAreKnownByTheirMarker() {
        XCTAssertTrue(AgentPaste.isOwnEvent(userData: AgentPaste.eventMarker))
        XCTAssertFalse(AgentPaste.isOwnEvent(userData: 0))
        XCTAssertFalse(AgentPaste.isOwnEvent(userData: AgentPaste.eventMarker + 1))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `xcodebuild test -scheme Locant -destination 'platform=macOS' -only-testing:LocantTests/AgentPasteTests 2>&1 | grep -E "error:|Executed|\*\* TEST"`
Expected: `error: cannot find 'AgentPaste' in scope` and `** TEST FAILED **`.

- [ ] **Step 3: Write the implementation**

Create `Locant/Payload/AgentPaste.swift`:

```swift
import Foundation

/// v0.8.1 R63: after Return, the capture is pasted into the agent app the user used last. The
/// decisions are pure and tested here; `AgentPaster` activates the app and posts the keys.
enum AgentPaste {
    /// Agent apps by exact bundle id, verified on this Mac on Sep 17, 2026. Never matched by name:
    /// ChatGPT Classic (`com.openai.chat`), CodexBar, and the Claude app's background-only Claude
    /// Code copies share words with these and are not agents.
    static let bundleIds: Set<String> = [
        "com.anthropic.claudefordesktop", // Claude
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.openai.codex", // Codex, installed as ChatGPT.app
    ]

    static func isAgent(bundleId: String?) -> Bool {
        bundleId.map { bundleIds.contains($0) } ?? false
    }

    /// Return is pressed in the agent only for a note with words in it, and only with the switch on.
    static func sends(note: String, enabled: Bool) -> Bool {
        enabled && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Beside the note field: the arrow and the app, then the window's title once it is known.
    struct TargetLabel: Equatable, Sendable {
        var lead: String
        var title: String?
    }

    static func label(appName: String?, windowTitle: String?) -> TargetLabel {
        guard let appName else { return TargetLabel(lead: "→ no agent yet", title: nil) }
        let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TargetLabel(lead: "→ \(appName)", title: (title?.isEmpty ?? true) ? nil : title)
    }

    /// How a paste ended.
    enum Outcome: Equatable, Sendable {
        case pasted, sent, noAgent, noPermission, didNotComeForward
    }

    /// What the toast says when nothing was pasted; nil when the paste itself is the feedback.
    static func toastText(_ outcome: Outcome, appName: String?) -> String? {
        switch outcome {
        case .pasted, .sent: nil
        case .noAgent: "Copied · no agent yet"
        case .noPermission: "Copied · pasting needs Accessibility"
        case .didNotComeForward: "Copied · \(appName ?? "the agent") didn't come forward"
        }
    }

    /// Marks the keys Locant posts, in `eventSourceUserData`, so its own tap lets them through.
    /// "LOCANT" in ASCII; nothing else sets it.
    static let eventMarker: Int64 = 0x4C_4F_43_41_4E_54

    static func isOwnEvent(userData: Int64) -> Bool {
        userData == eventMarker
    }
}
```

- [ ] **Step 4: Run it to see it pass**

Run: `xcodebuild test -scheme Locant -destination 'platform=macOS' -only-testing:LocantTests/AgentPasteTests 2>&1 | grep -E "error:|Executed|\*\* TEST"`
Expected: `Executed 5 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Locant/Payload/AgentPaste.swift LocantTests/AgentPasteTests.swift
git commit -m "paste: the pure decisions for pasting into the agent: which apps, when to send, the label, the toast"
```

---

### Task 2: The two switches (Preferences and Settings › Agents)

**Files:**
- Modify: `Locant/Store/Preferences.swift` (the `Key` enum near line 120; stored properties after `checksForUpdates` near line 271; `init` after the `checksForUpdates =` line near line 324)
- Modify: `Locant/App/SettingsView.swift` (the tab comment near lines 12-15; `AgentSettings` near line 631)
- Test: `LocantTests/PreferencesTests.swift` (`testDefaultsWhenNothingStored`, `testRoundTripThroughDefaults`)

**Interfaces:**
- Consumes: nothing.
- Produces (used by Tasks 4, 5): `Preferences.pastesIntoAgent: Bool`, `Preferences.sendsWithNote: Bool`, both persisted, both default `false`.

- [ ] **Step 1: Write the failing test**

In `LocantTests/PreferencesTests.swift`, in `testDefaultsWhenNothingStored`, after `XCTAssertTrue(p.collectsIterations)` add:

```swift
        XCTAssertFalse(p.pastesIntoAgent)
        XCTAssertFalse(p.sendsWithNote)
```

In `testRoundTripThroughDefaults`, after `p.collectsIterations = false` add:

```swift
        p.pastesIntoAgent = true
        p.sendsWithNote = true
```

and after `XCTAssertFalse(again.collectsIterations)` add:

```swift
        XCTAssertTrue(again.pastesIntoAgent)
        XCTAssertTrue(again.sendsWithNote)
```

- [ ] **Step 2: Run it to see it fail**

Run: `xcodebuild test -scheme Locant -destination 'platform=macOS' -only-testing:LocantTests/PreferencesTests 2>&1 | grep -E "error:|Executed|\*\* TEST"`
Expected: `error: value of type 'Preferences' has no member 'pastesIntoAgent'` and `** TEST FAILED **`.

- [ ] **Step 3: Add the preferences**

In `Locant/Store/Preferences.swift`, in `enum Key`, after `static let skippedUpdateVersion = "skippedUpdateVersion"` add:

```swift
        static let pastesIntoAgent = "pastesIntoAgent" // v0.8.1 R63
        static let sendsWithNote = "sendsWithNote" // v0.8.1 R63
```

After the `checksForUpdates` property (the block ending `didSet { defaults.set(checksForUpdates, forKey: Key.checksForUpdates) }` and its `}`) add:

```swift

    /// v0.8.1 R63: after Return, bring the agent app used last forward and paste the capture there.
    var pastesIntoAgent: Bool {
        didSet { defaults.set(pastesIntoAgent, forKey: Key.pastesIntoAgent) }
    }

    /// v0.8.1 R63: with a note, also press Return in the agent. Only while `pastesIntoAgent` is on.
    var sendsWithNote: Bool {
        didSet { defaults.set(sendsWithNote, forKey: Key.sendsWithNote) }
    }
```

In `init`, after `checksForUpdates = defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true` add:

```swift
        pastesIntoAgent = defaults.object(forKey: Key.pastesIntoAgent) as? Bool ?? false
        sendsWithNote = defaults.object(forKey: Key.sendsWithNote) as? Bool ?? false
```

- [ ] **Step 4: Run it to see it pass**

Run: `xcodebuild test -scheme Locant -destination 'platform=macOS' -only-testing:LocantTests/PreferencesTests 2>&1 | grep -E "error:|Executed|\*\* TEST"`
Expected: `0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Add the Settings section**

In `Locant/App/SettingsView.swift`, replace the tab comment line

```swift
        // Agents (v0.7.1 R56) is who fetches captures over MCP. The selection lives in AppState so
```

with

```swift
        // Agents (v0.7.1 R56, v0.8.1 R63) is where Return pastes and who fetches captures over MCP. The selection lives in AppState so
```

In `struct AgentSettings`, after `@State private var copied = false` add:

```swift
    @Environment(AppState.self) private var state
```

In `AgentSettings.body`, replace

```swift
    var body: some View {
        Form {
            Section {
                ForEach(Agent.allCases) { agent in
```

with

```swift
    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            // v0.8.1 R63: paste is the handoff, so it comes first; MCP below is how an agent looks back.
            Section {
                Toggle(isOn: $preferences.pastesIntoAgent) {
                    Text("Paste into your agent")
                    Text("After Return, Locant brings forward the agent app you used last, Claude, Cursor, or Codex, and pastes the capture there.")
                }
                .toggleStyle(.switch)
                Toggle(isOn: $preferences.sendsWithNote) {
                    Text("Send when there is a note")
                    Text("Locant also presses Return in the agent. Without a note, the capture waits in the message field.")
                }
                .toggleStyle(.switch)
                .disabled(!preferences.pastesIntoAgent)
                Footnote(text: "The note field shows where the capture will go. The clipboard holds it either way, and connected agents can still fetch it.")
            }
            Section {
                ForEach(Agent.allCases) { agent in
```

Only the second `Toggle` is disabled, never its `Section`: disabling a container is what hid text elsewhere in this file.

- [ ] **Step 6: Build and look**

Run: `xcodebuild build -scheme Locant -destination 'platform=macOS' 2>&1 | grep -E "error:|\*\* BUILD"`
Expected: `** BUILD SUCCEEDED **`.
Open the built app (see Task 4 Step 6 for how), Settings › Agents: the new section is first, both switches off, the second greyed until the first is on. The switches do nothing yet.

- [ ] **Step 7: Commit**

```bash
git add Locant/Store/Preferences.swift Locant/App/SettingsView.swift LocantTests/PreferencesTests.swift
git commit -m "settings: Paste into your agent and Send when there is a note, both off"
```

---

### Task 3: Bringing the agent forward and posting the keys (`AgentPaster`)

**Files:**
- Modify: `Locant/Resolve/AccessibilityReader.swift` (add two methods right after `focusedWindowTitle(pid:)`, near line 158)
- Modify: `Locant/Payload/AgentPaste.swift` (imports; append `AgentPaster`)
- Modify: `Locant/Capture/KeyEventTap.swift` (the `.keyDown, .flagsChanged` case of the callback, near line 56)

**Interfaces:**
- Consumes: `AgentPaste.eventMarker`, `AgentPaste.isOwnEvent(userData:)`, `AgentPaste.Outcome` (Task 1).
- Produces (used by Tasks 4, 5):
  - `AccessibilityReader.agentWindowTitle(pid: pid_t) -> String?` (actor method, `await` it)
  - `AccessibilityReader.raise(pid: pid_t)` (actor method)
  - `@MainActor enum AgentPaster` with `static func paste(into app: NSRunningApplication?, send: Bool, reader: AccessibilityReader) async -> AgentPaste.Outcome`

This task has no unit test: activation and posting need a running window server. The marker predicate it relies on is tested in Task 1; the whole path is checked by hand in Task 4.

- [ ] **Step 1: Add the two reader methods**

In `Locant/Resolve/AccessibilityReader.swift`, right after the closing `}` of `func focusedWindowTitle(pid: pid_t) -> String?`, add:

```swift

    // MARK: Paste into the agent (v0.8.1 R63)

    /// Title of an agent app's focused window, for the note field's target label. A short messaging
    /// timeout, so an app that does not answer costs a quarter second rather than the system's six.
    func agentWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let window = element(copy(app, kAXFocusedWindowAttribute)) ?? element(copy(app, kAXMainWindowAttribute)) else {
            return nil
        }
        AXUIElementSetMessagingTimeout(window, 0.25)
        return string(copy(window, kAXTitleAttribute))
    }

    /// Brings an app forward through accessibility when `activate()` was not honored, as for a
    /// window on another Space: the app becomes frontmost and its main window is raised.
    func raise(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let window = element(copy(app, kAXMainWindowAttribute)) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }
```

`copy(_:_:)`, `element(_:)` and `string(_:)` are the reader's existing private helpers (near lines 331-342).

- [ ] **Step 2: Build**

Run: `xcodebuild build -scheme Locant -destination 'platform=macOS' 2>&1 | grep -E "error:|\*\* BUILD"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Add `AgentPaster`**

In `Locant/Payload/AgentPaste.swift`, replace the first line

```swift
import Foundation
```

with

```swift
import AppKit
import Carbon.HIToolbox
```

Then append at the end of the file:

```swift

/// v0.8.1 R63: brings the agent app forward and posts ⌘V, then Return when asked. Not pure; not unit
/// tested. Every step checks the agent is still in front, so a key never lands in the app the user
/// pointed at.
@MainActor
enum AgentPaster {
    /// After the agent is frontmost, before ⌘V: Electron puts focus back in its composer.
    static let settle: Duration = .milliseconds(150)
    /// Between ⌘V and Return: Electron paste handlers, and an image attachment most of all, finish
    /// after the key. Tuned in dogfood.
    static let sendGap: Duration = .milliseconds(400)

    static func paste(into app: NSRunningApplication?, send: Bool, reader: AccessibilityReader) async -> AgentPaste.Outcome {
        guard let app, !app.isTerminated else { return .noAgent }
        guard CGPreflightPostEventAccess() else { return .noPermission }
        await waitForKeysUp()
        guard await bringForward(app, reader: reader) else { return .didNotComeForward }
        try? await Task.sleep(for: settle)
        guard isFrontmost(app) else { return .didNotComeForward }
        post(keyCode: pasteKeyCode(), flags: .maskCommand)
        guard send else { return .pasted }
        try? await Task.sleep(for: sendGap)
        guard isFrontmost(app) else { return .pasted }
        post(keyCode: CGKeyCode(kVK_Return), flags: [])
        return .sent
    }

    /// The Return that committed the note, and any modifier still held, must be up first, or they
    /// leak into the posted keys. Half a second at most.
    private static func waitForKeysUp() async {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        for _ in 0..<20 {
            let returnDown = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(kVK_Return))
            let held = !CGEventSource.flagsState(.hidSystemState).intersection(modifiers).isEmpty
            if !returnDown, !held { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// Activates, then polls every 25 ms for a second: a notification never comes when the app is
    /// already in front. After 300 ms, accessibility raises it, which reaches a window on another Space.
    private static func bringForward(_ app: NSRunningApplication, reader: AccessibilityReader) async -> Bool {
        if isFrontmost(app) { return true }
        _ = app.activate(options: [])
        for tick in 1...40 {
            try? await Task.sleep(for: .milliseconds(25))
            if isFrontmost(app) { return true }
            if app.isTerminated { return false }
            if tick == 12 { await reader.raise(pid: app.processIdentifier) }
        }
        return false
    }

    private static func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    /// Key down and up with the flags on the events themselves: separate Command events would feed
    /// the double-tap detector. Marked, so Locant's own tap lets them through.
    private static func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: AgentPaste.eventMarker)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// The key that makes ⌘V on the current layout: the ASCII-capable one, so an active Chinese or
    /// Japanese input method still finds it, read with Command held, so "Dvorak – QWERTY ⌘" pastes
    /// too. ANSI V when the layout cannot be read.
    private static func pasteKeyCode() -> CGKeyCode {
        let fallback = CGKeyCode(kVK_ANSI_V)
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        let command = UInt32((cmdKey >> 8) & 0xFF)
        let found = data.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in CGKeyCode(0)..<CGKeyCode(128) {
                var deadKeys: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDown), command, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, characters.count, &length, &characters
                )
                if status == noErr, length == 1, characters[0] == UniChar(0x76) { return code } // "v"
            }
            return nil
        }
        return found ?? fallback
    }
}
```

- [ ] **Step 4: Let Locant's own keys through its tap**

In `Locant/Capture/KeyEventTap.swift`, in the callback, replace

```swift
            case .keyDown, .flagsChanged:
                let keyEvent = KeyEvent(
```

with

```swift
            case .keyDown, .flagsChanged:
                // v0.8.1 R63: the keys Locant posts to paste into an agent pass untouched, so a hotkey
                // recorded as ⌘V or ⌘↩ cannot swallow Locant's own paste.
                if AgentPaste.isOwnEvent(userData: event.getIntegerValueField(.eventSourceUserData)) {
                    return Unmanaged.passUnretained(event)
                }
                let keyEvent = KeyEvent(
```

- [ ] **Step 5: Build and run every test**

Run: `xcodebuild test -scheme Locant -destination 'platform=macOS' 2>&1 | grep -E "error:|Executed [0-9]+ tests|\*\* TEST" | tail -3`
Expected: `Executed 164 tests, with 0 failures` (159 before this plan, plus Task 1's 5) and `** TEST SUCCEEDED **`. If the compiler rejects `app.activate(options: [])` as an unused result or a deprecation, keep `_ =` and the empty options; do not add `.activateIgnoringOtherApps`, which macOS 14+ ignores.

- [ ] **Step 6: Commit**

```bash
git add Locant/Resolve/AccessibilityReader.swift Locant/Payload/AgentPaste.swift Locant/Capture/KeyEventTap.swift
git commit -m "paste: bring the agent forward and post ⌘V and Return, marked so Locant's own tap lets them through"
```

---

### Task 4: Wiring it into Return (`AppState`)

**Files:**
- Modify: `Locant/App/AppState.swift`: properties after `@ObservationIgnored private var collecting = false` (near line 69); `start()` (near line 97); a new section after `watchAppsForIterations()` (near line 216); the first guard of `appCameForward` (near line 296); the end of `commit(note:)` (near line 941).

**Interfaces:**
- Consumes: `AgentPaste.isAgent(bundleId:)`, `AgentPaste.sends(note:enabled:)`, `AgentPaste.toastText(_:appName:)` (Task 1); `Preferences.pastesIntoAgent`, `Preferences.sendsWithNote` (Task 2); `AgentPaster.paste(into:send:reader:)` (Task 3).
- Produces (used by Task 5): `AppState.lastAgent: NSRunningApplication?` (private computed), `AppState.agentReader: AccessibilityReader` (private).

- [ ] **Step 1: Add the state**

After `@ObservationIgnored private var collecting = false` add:

```swift
    /// v0.8.1 R63: the agent app that came forward last, by pid; `lastAgent` checks it is still that app.
    @ObservationIgnored private var lastAgentPID: pid_t?
    /// v0.8.1 R63: a reader of its own for the target label, so a slow agent never holds up hover.
    @ObservationIgnored private let agentReader = AccessibilityReader()
    /// v0.8.1 R63: true while Locant brings an agent forward to paste; auto-verify ignores that activation.
    @ObservationIgnored private var pasting = false
```

- [ ] **Step 2: Record the last agent**

In `start()`, after `watchAppsForIterations()` add:

```swift
        watchAgentApps()
```

After the closing `}` of `private func watchAppsForIterations()` add:

```swift

    // MARK: Paste into the agent (v0.8.1 R63)

    /// Remembers the agent app that came forward last. An observer of its own: `appCameForward`
    /// returns early while iterations are off or a capture runs, and would drop these.
    private func watchAgentApps() {
        let center = NSWorkspace.shared.notificationCenter
        appObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  AgentPaste.isAgent(bundleId: app.bundleIdentifier) else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.lastAgentPID = pid }
        })
    }

    /// The last agent while it still runs as the same app; nil after it quits.
    private var lastAgent: NSRunningApplication? {
        guard let pid = lastAgentPID, let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated, AgentPaste.isAgent(bundleId: app.bundleIdentifier) else { return nil }
        return app
    }

    /// After the clipboard: wait for the overlay to order out, so no Locant panel is key, then bring
    /// the last agent forward and paste; Return too for a note when the second switch is on. Skipped
    /// when another capture has started meanwhile. The toast speaks only when nothing was pasted.
    private func pasteIntoAgent(note: String, near anchor: CGRect) async {
        let send = AgentPaste.sends(note: note, enabled: preferences.sendsWithNote)
        try? await Task.sleep(for: .milliseconds(Int(DesignTokens.dismiss * 1000) + 40))
        guard phase == .idle else { return }
        let app = lastAgent
        pasting = true
        let outcome = await AgentPaster.paste(into: app, send: send, reader: agentReader)
        pasting = false
        if let text = AgentPaste.toastText(outcome, appName: app?.localizedName) {
            toast.show(HudText.plain(text), near: anchor)
        }
    }
```

- [ ] **Step 3: Keep auto-verify off the paste**

In `appCameForward(bundleId:pid:)`, replace

```swift
        guard preferences.collectsIterations, phase == .idle, !collecting else { return }
```

with

```swift
        guard preferences.collectsIterations, phase == .idle, !collecting, !pasting else { return }
```

- [ ] **Step 4: Paste after Return**

At the end of `commit(note:)`, replace the single line

```swift
                showAgentHintIfNeeded()
```

with

```swift
                // v0.8.1 R63: with the option on, the hint about fetching over MCP stays unspent.
                if preferences.pastesIntoAgent {
                    await pasteIntoAgent(note: note, near: anchor)
                } else {
                    showAgentHintIfNeeded()
                }
```

It runs after `store.write`, `PasteboardWriter.write`, `reset()` and the toast, so a failed capture still reaches `fail(...)` and touches nothing.

- [ ] **Step 5: Build and run every test**

Run: `xcodebuild test -scheme Locant -destination 'platform=macOS' 2>&1 | grep -E "error:|Executed [0-9]+ tests|\*\* TEST" | tail -3`
Expected: `Executed 164 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 6: Check it by hand**

Quit the installed Locant first (two copies would fight over the hotkeys), then open the debug build:

```bash
osascript -e 'tell application "Locant" to quit'
open "$(xcodebuild -scheme Locant -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3; exit}')/Locant.app"
```

macOS ties Accessibility and Screen Recording to the signature; if the debug build cannot capture, grant it in System Settings › Privacy & Security.

Use a throwaway chat in the agent: step 4 sends a message.

1. Settings › Agents: turn on Paste into your agent. Leave Send when there is a note off.
2. Click into a Cursor or Claude chat's message field, so it is the last agent.
3. Switch to any other app. ⌃⌃, click an element, leave the note empty, Return.
   Expected: the agent comes forward and the payload lands in its message field, not sent. The Copied toast shows as before.
4. Turn on Send when there is a note. Repeat with the note `test, ignore`.
   Expected: pasted and sent.
5. Quit the agent app. Point and Return.
   Expected: toast `Copied · no agent yet`; clipboard holds the payload.
6. Turn Paste into your agent off. Point and Return.
   Expected: exactly today's behavior.

Note what each agent did with the pasted item (text, image, or both) for Task 6.

- [ ] **Step 7: Commit**

```bash
git add Locant/App/AppState.swift
git commit -m "paste: Return pastes into the agent used last when the option is on"
```

---

### Task 5: Where it will go, beside the note field

**Files:**
- Modify: `Locant/Capture/SelectionOverlay.swift`: `HudText` (near line 62); `SelectionOverlay` after `showNoteField(anchoredTo:around:)` (near line 200); `OverlayContentView` properties (near line 292), `init` (near line 320), `showNoteField(screenRect:)` (near line 601), and a new method after it.
- Modify: `Locant/App/AppState.swift`: the three `overlay.showNoteField(...)` calls (near lines 732, 758, 808) and a new wrapper in the paste section from Task 4.

**Interfaces:**
- Consumes: `AgentPaste.label(appName:windowTitle:)`, `AgentPaste.TargetLabel` (Task 1); `Preferences.pastesIntoAgent` (Task 2); `AccessibilityReader.agentWindowTitle(pid:)` (Task 3); `AppState.lastAgent`, `AppState.agentReader` (Task 4).
- Produces: `HudText.pasteTarget(_:)`, `SelectionOverlay.setNoteTarget(_:)`, `OverlayContentView.setNoteTarget(_:)`, `OverlayContentView.hasNoteField`.

No unit test: the label text is `AgentPaste.label`, tested in Task 1; placement is UI, which the house rules leave to eyes.

- [ ] **Step 1: The attributed label**

In `enum HudText`, after `static func plain(_:)` add:

```swift

    /// v0.8.1 R63: "→ Cursor · <window title>" beside the note field, the title secondary.
    static func pasteTarget(_ label: AgentPaste.TargetLabel) -> NSAttributedString {
        let s = NSMutableAttributedString(string: label.lead, attributes: sansAttributes)
        if let title = label.title {
            s.append(NSAttributedString(string: " · ", attributes: sansAttributes))
            s.append(NSAttributedString(string: title, attributes: secondaryAttributes))
        }
        return s
    }
```

- [ ] **Step 2: The label view**

In `OverlayContentView`, after `private var noteField: NoteFieldView?` add:

```swift
    /// v0.8.1 R63: where Return will paste, and the element the field is anchored to (local coordinates).
    private let targetLabel = HudLabel()
    private var noteAnchor: CGRect = .zero
```

In its `init`, after `addSubview(sizeLabel)` add:

```swift
        targetLabel.isHidden = true
        addSubview(targetLabel)
```

In `showNoteField(screenRect:)`, after the line `let local = convert(window.convertFromScreen(screenRect), from: nil)` add:

```swift
        noteAnchor = local
```

After the closing `}` of `showNoteField(screenRect:)` add:

```swift

    var hasNoteField: Bool { noteField != nil }

    /// v0.8.1 R63: where Return will paste, on the far side of the note field from the element and
    /// left-aligned with it; kept on screen. Nil hides it.
    func setNoteTarget(_ text: NSAttributedString?) {
        guard let field = noteField, let text else {
            targetLabel.isHidden = true
            return
        }
        targetLabel.set(text)
        let size = targetLabel.hudSize
        var origin = CGPoint(x: field.frame.minX, y: field.frame.minY - DesignTokens.spaceS - size.height)
        if field.frame.midY > noteAnchor.midY { // the field flipped above the element
            origin.y = field.frame.maxY + DesignTokens.spaceS
        }
        origin.x = min(max(origin.x, DesignTokens.spaceM), bounds.width - size.width - DesignTokens.spaceM)
        origin.y = min(max(origin.y, DesignTokens.spaceM), bounds.height - size.height - DesignTokens.spaceM)
        targetLabel.frame = CGRect(origin: origin, size: size)
        targetLabel.isHidden = false
    }
```

The panels, and this label with them, are created fresh by every `show()`, so nothing needs clearing.

- [ ] **Step 3: The controller's entry point**

In `SelectionOverlay`, after the closing `}` of `func showNoteField(anchoredTo frame: CGRect?, around point: CGPoint)` add:

```swift

    /// v0.8.1 R63: where Return will paste, beside the note field; nil hides it.
    func setNoteTarget(_ text: NSAttributedString?) {
        panels.first { $0.contentOverlay.hasNoteField }?.contentOverlay.setNoteTarget(text)
    }
```

- [ ] **Step 4: Show it from AppState**

In `Locant/App/AppState.swift`, replace each of these three lines (one in the single-element click path, one in `finishSet`, one in `region`):

```swift
            overlay.showNoteField(anchoredTo: element?.frame.cgRect, around: point)
```
```swift
        overlay.showNoteField(anchoredTo: last.frame.cgRect, around: point)
```
```swift
            overlay.showNoteField(anchoredTo: rect, around: clickPoint)
```

with, respectively:

```swift
            showNoteField(anchoredTo: element?.frame.cgRect, around: point)
```
```swift
        showNoteField(anchoredTo: last.frame.cgRect, around: point)
```
```swift
            showNoteField(anchoredTo: rect, around: clickPoint)
```

Then, in the `// MARK: Paste into the agent (v0.8.1 R63)` section added in Task 4, after `watchAgentApps()`'s closing `}`, add:

```swift

    /// The note field, and beside it where Return will paste when that option is on.
    private func showNoteField(anchoredTo frame: CGRect?, around point: CGPoint) {
        overlay.showNoteField(anchoredTo: frame, around: point)
        showPasteTarget()
    }

    /// The app at once; its window title when the agent's own reader answers, if the field is
    /// still open by then.
    private func showPasteTarget() {
        guard preferences.pastesIntoAgent else { return }
        guard let app = lastAgent else {
            overlay.setNoteTarget(HudText.pasteTarget(AgentPaste.label(appName: nil, windowTitle: nil)))
            return
        }
        let name = app.localizedName ?? "Agent"
        overlay.setNoteTarget(HudText.pasteTarget(AgentPaste.label(appName: name, windowTitle: nil)))
        let pid = app.processIdentifier
        Task { @MainActor in
            let title = await agentReader.agentWindowTitle(pid: pid)
            guard phase == .noting else { return }
            overlay.setNoteTarget(HudText.pasteTarget(AgentPaste.label(appName: name, windowTitle: title)))
        }
    }
```

Check: `grep -n "overlay.showNoteField" Locant/App/AppState.swift` must print exactly one line, the one inside the new wrapper.

- [ ] **Step 5: Build and run every test**

Run: `xcodebuild test -scheme Locant -destination 'platform=macOS' 2>&1 | grep -E "error:|Executed [0-9]+ tests|\*\* TEST" | tail -3`
Expected: `Executed 164 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 6: Check it by hand**

With the debug build from Task 4 Step 6 and Paste into your agent on:

1. Click into Cursor. Switch away. ⌃⌃, click an element.
   Expected: under the note field (or above it, when the field flipped above the element), `→ Cursor`, then `→ Cursor · <window title>` a moment later.
2. Point near the bottom of the screen, so the field flips above the element.
   Expected: the label sits above the field, not over the element.
3. Quit every agent app, point.
   Expected: `→ no agent yet`.
4. Turn the option off, point.
   Expected: no label.

Write down the raw window titles each app showed, for Task 6.

- [ ] **Step 7: Commit**

```bash
git add Locant/Capture/SelectionOverlay.swift Locant/App/AppState.swift
git commit -m "overlay: the note field shows where Return will paste"
```

---

### Task 6: Dogfood, and write down what it found

**Files:**
- Modify: `specs/v0.8.1-paste.md` (append a `### Dogfood notes` section under R63)

No code unless a check fails. Run the option on for a normal working day, then answer the spec's five checks in `specs/v0.8.1-paste.md`, dated, one line each:

- [ ] **1.** What Claude, Cursor, and ChatGPT each took from the one item carrying PNG and Markdown: text, image attachment, or both. If one took only the image, that is a spec change (text-only item for that app, then the full item written back); stop and bring it back to the spec, do not patch it here.
- [ ] **2.** How often ⌘V landed in Cursor's code editor instead of its chat.
- [ ] **3.** Whether the agent came forward every time, including from another Space and from full screen; how often `Copied · … didn't come forward` appeared.
- [ ] **4.** Whether focus moving to the agent on every Return fit the normal workflow.
- [ ] **5.** The raw window titles seen in Task 5 for each app, as samples for a later workspace parser.

- [ ] **Commit the notes**

```bash
git add specs/v0.8.1-paste.md
git commit -m "specs: v0.8.1 R63 dogfood notes"
```
