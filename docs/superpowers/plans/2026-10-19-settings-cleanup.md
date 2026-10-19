# Settings Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Settings row becomes a title and a control, and the help page, menu bar menu, alerts, and docs follow (`specs/settings-cleanup.md`, R91–R100).

**Architecture:** View-layer changes in `Locant/App/SettingsView.swift`, `HelpView.swift`, and `LocantApp.swift`, plus two wording changes in pure code (`HotkeyConflict.message`, and a new pure `HotkeyRecorder.press` that decides what a key does while recording). No preference, model, or schema change. Pure code gets XCTest tests; the views are checked on screen in a scratch Debug build.

**Tech Stack:** Swift 6 (strict concurrency complete), SwiftUI `Form` with `.formStyle(.grouped)`, AppKit, XCTest. No packages.

## Global Constraints

- No preference key added, removed, or renamed; no default changes (spec, Out of scope).
- A Settings row is a title and a control; the only extra words are a missing permission's row, a hotkey clash line, an agent's failure line, and the empty My Apps line; the only group header is "MCP" (R91).
- A button that acts at once has no ellipsis (R91).
- Commit messages: `area: what changed`; never commit without a green build (`docs/CLAUDE.md`). No attribution lines.
- Code comments match the file's density and voice; cite the requirement (R9x) where the old code cited one.

Shell setup used by every task (zsh):

```bash
cd /Users/malik/Documents/Locant/.claude/worktrees/settings-simplification-084f77
DD=/private/tmp/claude-501/-Users-malik-Documents-Locant--claude-worktrees-settings-simplification-084f77/e2eb2731-336f-4a78-a5b6-fcddc5cde6c2/scratchpad/dd
```

Build: `xcodebuild -project Locant.xcodeproj -scheme Locant -configuration Debug -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet` (expected: no output, exit 0).
Tests: `xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' -derivedDataPath "$DD" test -quiet <-only-testing:…>` (expected: exit 0; the log ends with `** TEST SUCCEEDED **` without `-quiet`).

---

### Task 1: Clash lines name Point (R93)

**Files:**
- Modify: `Locant/Capture/HotkeyConflicts.swift:13-18`
- Test: `LocantTests/HotkeyTests.swift` (end of `testCheckReportsLocantClashFirst`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `HotkeyConflict.message` reads "Already used for Point." for `.locant(action: "capture")` and "Also a macOS shortcut; Locant takes it first." for `.system`.

- [ ] **Step 1: Write the failing test.** Append to `testCheckReportsLocantClashFirst`, after the `"snap"` assertion:

```swift
        XCTAssertEqual(HotkeyConflict.locant(action: "capture").message, "Already used for Point.")
        XCTAssertEqual(HotkeyConflict.system.message, "Also a macOS shortcut; Locant takes it first.")
```

- [ ] **Step 2: Run it to see it fail.** `xcodebuild … test -quiet -only-testing:LocantTests/HotkeyTests` → FAIL: `("Already used for Capture.") is not equal to ("Already used for Point.")`.

- [ ] **Step 3: Implement.** In `HotkeyConflict.message`:

```swift
    var message: String {
        switch self {
        // R93: the capture hotkey shares Point's row, so a clash with it names Point.
        case .locant(let action): "Already used for \(action == "capture" ? "Point" : action.capitalized)."
        case .system: "Also a macOS shortcut; Locant takes it first."
        }
    }
```

- [ ] **Step 4: Run the test to see it pass.** Same command → exit 0.

- [ ] **Step 5: Commit.** `git add Locant/Capture/HotkeyConflicts.swift LocantTests/HotkeyTests.swift && git commit -m "hotkeys: a clash with the capture hotkey names Point"`

---

### Task 2: The recorder clears only while recording (R93)

**Files:**
- Modify: `Locant/App/SettingsView.swift` (`HotkeyRecorder`, lines 424–552)
- Test: `LocantTests/HotkeyTests.swift` (a new `// MARK: Recorder (R93)` section at the end of the class; no new file, per `docs/CLAUDE.md`)

**Interfaces:**
- Consumes: `Hotkey.chord(keyCode:modifiers:key:)`, `KeyModifiers`, `KeyModifiers(_ flags: NSEvent.ModifierFlags)` (`HotkeyMonitor.swift:159`).
- Produces: `HotkeyRecorder.Press` (`.cancel`, `.clear`, `.needsModifier`, `.ignore`, `.record(Hotkey)`) and `static func press(keyCode: UInt16, modifiers: KeyModifiers, characters: String?, canClear: Bool) -> Press` (main-actor isolated, as the view is).

- [ ] **Step 1: Write the failing tests** at the end of `HotkeyTests` (the class is already `@MainActor`, as `HotkeyRecorder` is):

```swift
    // MARK: Recorder (R93)

    private func press(_ keyCode: UInt16, _ modifiers: KeyModifiers = [], _ characters: String? = nil, canClear: Bool = true) -> HotkeyRecorder.Press {
        HotkeyRecorder.press(keyCode: keyCode, modifiers: modifiers, characters: characters, canClear: canClear)
    }

    func testRecorderEscCancels() {
        XCTAssertEqual(press(53), .cancel)
        XCTAssertEqual(press(53, [.command]), .cancel)
    }

    func testRecorderDeleteAloneClearsWhenTheHotkeyMayBeEmpty() {
        XCTAssertEqual(press(51), .clear, "⌫")
        XCTAssertEqual(press(117), .clear, "⌦")
    }

    func testRecorderDeleteAloneNeedsAModifierWhenTheHotkeyMustStay() {
        XCTAssertEqual(press(51, canClear: false), .needsModifier)
        XCTAssertEqual(press(117, canClear: false), .needsModifier)
    }

    func testRecorderDeleteWithModifiersIsAChord() {
        XCTAssertEqual(press(51, [.control, .option]), .record(.chord(keyCode: 51, modifiers: [.control, .option], key: "⌫")))
    }

    func testRecorderBareKeyNeedsAModifierAndAFunctionKeyDoesNot() {
        XCTAssertEqual(press(0, [], "a"), .needsModifier)
        XCTAssertEqual(press(96), .record(.chord(keyCode: 96, modifiers: [], key: "F5")))
    }

    func testRecorderChordTakesTheKeyInCapitals() {
        XCTAssertEqual(press(2, [.command, .shift], "d"), .record(.chord(keyCode: 2, modifiers: [.command, .shift], key: "D")))
    }

    func testRecorderKeyWithNoNameIsIgnored() {
        XCTAssertEqual(press(0, [.command], ""), .ignore)
    }
```

- [ ] **Step 2: Run them to see them fail.** `xcodebuild … test -quiet -only-testing:LocantTests/HotkeyTests` → build error: `type 'HotkeyRecorder' has no member 'Press'`.

- [ ] **Step 3: Implement.** In `HotkeyRecorder`, replace the doc comment, add `deleteKeys` and `canClear` after `specialKeys`, and replace `body`:

```swift
/// Records the next key press or modifier double-tap as the hotkey. Esc cancels. R93: at rest only
/// Reset shows, and only when the key is not the default; Clear shows while recording, and ⌫ or ⌦
/// alone clears too.
struct HotkeyRecorder: View {
```

```swift
    /// ⌫ and ⌦: alone, they clear (R93).
    private static let deleteKeys: Set<UInt16> = [51, 117]

    /// Whether the action may be left without a hotkey; implied when there is no fallback.
    private var canClear: Bool { clearable || fallback == nil }

    var body: some View {
        // The width sits on the label so the bordered button itself is the fixed-width control;
        // a frame on the button would leave invisible space around a short title.
        HStack(spacing: 8) {
            if recording {
                if hotkey != nil, canClear {
                    Button("Clear") {
                        hotkey = nil
                        stop()
                    }
                }
            } else if let fallback, hotkey != fallback {
                Button("Reset") { hotkey = fallback }
            }
            Button {
                recording ? stop() : begin()
            } label: {
                Text(recording ? (hint ?? "Press keys…") : (hotkey?.title ?? "None"))
                    .lineLimit(1)
                    .frame(minWidth: 120)
            }
        }
        .fixedSize()
    }

    /// What a key pressed while recording does.
    enum Press: Equatable {
        case cancel, clear, needsModifier, ignore
        case record(Hotkey)
    }

    /// Esc cancels; ⌫ or ⌦ alone clears when the hotkey may be left empty (R93); any other key needs
    /// a modifier unless it is a function key. Pure, so the tests press keys without a monitor.
    static func press(keyCode: UInt16, modifiers: KeyModifiers, characters: String?, canClear: Bool) -> Press {
        if keyCode == 53 { return .cancel }
        if modifiers.isEmpty, canClear, deleteKeys.contains(keyCode) { return .clear }
        let name = functionKeys[keyCode] ?? specialKeys[keyCode] ?? (characters ?? "").uppercased()
        guard !name.isEmpty else { return .ignore }
        if modifiers.isEmpty, functionKeys[keyCode] == nil { return .needsModifier }
        return .record(.chord(keyCode: keyCode, modifiers: modifiers, key: name))
    }
```

Replace the `case .keyDown:` branch of `handle(type:keyCode:flags:characters:timestamp:)`:

```swift
        case .keyDown:
            switch Self.press(keyCode: keyCode, modifiers: KeyModifiers(flags), characters: characters, canClear: canClear) {
            case .cancel:
                stop()
            case .clear:
                hotkey = nil
                stop()
            case .needsModifier:
                hint = "Add ⌘, ⌥, ⌃ or ⇧"
            case .record(let chord):
                if let reason = rejects(chord) {
                    hint = reason
                    return
                }
                hotkey = chord
                stop()
            case .ignore:
                break
            }
```

The `.flagsChanged` branch is unchanged.

- [ ] **Step 4: Run the tests to see them pass.** Same command → exit 0.

- [ ] **Step 5: Commit.** `git add Locant/App/SettingsView.swift LocantTests/HotkeyTests.swift && git commit -m "settings: Clear shows only while recording a hotkey, and ⌫ clears"`

---

### Task 3: Hotkeys tab, one row per action (R93)

**Files:**
- Modify: `Locant/App/SettingsView.swift` (`HotkeySettings`, lines 286–349)

**Interfaces:**
- Consumes: `HotkeyRecorder` (Task 2), `ConflictNote`, `Preferences.hotkeyActions`, `Preferences.defaultActionHotkey(_:)`, `preferences.setActionHotkey(_:for:)`.
- Produces: nothing new.

- [ ] **Step 1: Replace the doc comment and `body`** of `HotkeySettings` (keep `rejection(for:action:)` and `refreshConflicts()` as they are):

```swift
/// R51, R93: one row per action, in menu and ring order. Point's row also carries the capture
/// hotkey, so both keys that start Point sit together; each clash shows under its row.
struct HotkeySettings: View {
    @Environment(AppState.self) private var state
    /// R29: a warning under each hotkey row, by action name ("capture" for the capture hotkey).
    @State private var conflicts: [String: String] = [:]

    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            Section {
                ForEach(Preferences.hotkeyActions, id: \.self) { action in
                    // System Settings row: the title leading, the recorders trailing.
                    LabeledContent {
                        HStack(spacing: 8) {
                            if action == "point" {
                                HotkeyRecorder(
                                    hotkey: Binding(get: { preferences.hotkey }, set: { preferences.hotkey = $0 ?? .default }),
                                    fallback: .default,
                                    rejects: { rejection(for: $0, action: "capture") },
                                    onBegin: { state.pauseHotkey() }, onEnd: { state.resumeHotkey() }
                                )
                            }
                            HotkeyRecorder(
                                hotkey: Binding(get: { preferences.actionHotkeys[action] }, set: { preferences.setActionHotkey($0, for: action) }),
                                fallback: Preferences.defaultActionHotkey(action),
                                clearable: true,
                                rejects: { rejection(for: $0, action: action) },
                                onBegin: { state.pauseHotkey() }, onEnd: { state.resumeHotkey() }
                            )
                        }
                    } label: {
                        Text(action.capitalized)
                        if action == "point", let warning = conflicts["capture"] { ConflictNote(text: warning) }
                        if let warning = conflicts[action] { ConflictNote(text: warning) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { refreshConflicts() }
        .onChange(of: preferences.hotkey) { refreshConflicts() }
        .onChange(of: preferences.actionHotkeys) { refreshConflicts() }
    }
```

- [ ] **Step 2: Build.** Build command → exit 0, no output.

- [ ] **Step 3: Commit.** `git commit -am "settings: Hotkeys is one row per action, Point with both of its keys"`

---

### Task 4: General tab (R91, R92)

**Files:**
- Modify: `Locant/App/SettingsView.swift` (`PermissionRow` lines 106–136, `GeneralSettings` lines 152–272, and `AgentRow`'s green, line 773)

**Interfaces:**
- Consumes: `state.previewSound()`, `state.previewTap()`, `state.checkForUpdates(manual:)`, `state.diagnosticsText()`, `UpdateCheck.currentVersion`.
- Produces: `PermissionRow(title:grant:)`; `AgentRow.connectedGreen` (private static, used by Task 7).

- [ ] **Step 1: Replace `PermissionRow`:**

```swift
/// R92: a missing permission, the way System Settings flags one: the orange mark and a way to grant
/// it. A granted permission has no row.
private struct PermissionRow: View {
    let title: String
    let grant: () -> Void

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.orange)
                Button("Grant…", action: grant)
            }
        }
    }
}
```

- [ ] **Step 2: Move the green into `AgentRow`.** Add as the first member of `AgentRow`, and change `PermissionRow.grantedGreen` in its body to `Self.connectedGreen`:

```swift
    /// Apple's macOS system green as the light appearance draws it (#28CD41). The dark appearance
    /// lightens its green by design, and on a 13 pt tick that read as pale and washed out
    /// (Malik, Sep 14 2026), so the light value is pinned in both appearances. Measured in the dark
    /// grouped Form: `.green` renders P3 #68CE67, this renders #63CA56, same lightness, more chroma.
    private static let connectedGreen = Color(red: 0x28 / 255.0, green: 0xCD / 255.0, blue: 0x41 / 255.0)
```

- [ ] **Step 3: Replace `GeneralSettings.body`** (properties and the two private helpers stay; the `checking` comment loses its ellipsis, the `copiedDiagnostics` comment says "Copy"):

```swift
    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            // R92: a permission shows only while it is missing.
            if !accessibilityGranted || !screenRecordingGranted {
                Section {
                    if !accessibilityGranted {
                        PermissionRow(title: "Accessibility") {
                            _ = AccessibilityReader.isTrusted(prompt: true)
                            openPrivacyPane("Privacy_Accessibility")
                        }
                    }
                    if !screenRecordingGranted {
                        PermissionRow(title: "Screen Recording") {
                            _ = ScreenCapture.requestPermission()
                            openPrivacyPane("Privacy_ScreenCapture")
                        }
                    }
                }
            }
            Section {
                Toggle("Floating ball", isOn: $preferences.ballEnabled)
                Toggle("Auto-hide", isOn: $preferences.ballAutoHide)
                    .disabled(!preferences.ballEnabled)
            }
            Section {
                Toggle("Sounds", isOn: $preferences.sounds)
                    .onChange(of: preferences.sounds) { _, on in
                        if on { state.previewSound() }
                    }
                Toggle("Haptic feedback", isOn: $preferences.trackpadTaps)
                    .onChange(of: preferences.trackpadTaps) { _, on in
                        if on { state.previewTap() }
                    }
            }
            Section {
                Toggle("Check for updates automatically", isOn: $preferences.checksForUpdates)
                LabeledContent("Version \(UpdateCheck.currentVersion?.description ?? "unknown")") {
                    Button("Check Now") {
                        checking = true
                        Task {
                            await state.checkForUpdates(manual: true)
                            checking = false
                        }
                    }
                    .disabled(checking)
                }
                // v0.9 R71: one block for an issue, copied by hand and never sent.
                LabeledContent("Diagnostics") {
                    Button(copiedDiagnostics ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.diagnosticsText(), forType: .string)
                        copiedDiagnostics = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedDiagnostics = false
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .task {
            while !Task.isCancelled {
                refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
```

- [ ] **Step 4: Build.** Build command → exit 0.

- [ ] **Step 5: Commit.** `git commit -am "settings: General is titles and switches, permissions only when missing"`

---

### Task 5: Captures tab (R94)

**Files:**
- Modify: `Locant/App/SettingsView.swift` (`CaptureSettings`, lines 351–408)

**Interfaces:**
- Consumes: `preferences.captureFolder`, `organization`, `retentionDays`, `adjustSelection`, `collectsIterations`, `colorFormat`, `colorSpace`; `chooseFolder(_:)` (unchanged).
- Produces: nothing new.

- [ ] **Step 1: Replace the doc comment and `body`** (keep `chooseFolder`):

```swift
/// R51, R94: where captures go and how long they stay, the selection handles and recapturing, and
/// the Color format.
struct CaptureSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            Section {
                LabeledContent("Save to") {
                    HStack(spacing: 8) {
                        Text((preferences.captureFolder as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseFolder(preferences) }
                    }
                }
                Picker("Organize", selection: $preferences.organization) {
                    ForEach(CaptureOrganization.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("Keep captures", selection: $preferences.retentionDays) {
                    ForEach(Preferences.retentionChoices, id: \.self) { days in
                        Text(days == 0 ? "Forever" : "\(days) days").tag(days)
                    }
                }
            }
            Section {
                Toggle("Adjust selection before capturing", isOn: $preferences.adjustSelection)
                Toggle("Recapture when your app changes", isOn: $preferences.collectsIterations)
            }
            Section {
                Picker("Color format", selection: $preferences.colorFormat) {
                    ForEach(ColorFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Color space", selection: $preferences.colorSpace) {
                    ForEach(ColorSpaceChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .pickerStyle(.menu)
        .toggleStyle(.switch)
    }
```

- [ ] **Step 2: Build.** Build command → exit 0.

- [ ] **Step 3: Commit.** `git commit -am "settings: Captures shows the folder as a path, no footnotes"`

---

### Task 6: My Apps tab (R95)

**Files:**
- Modify: `Locant/App/SettingsView.swift` (`MyAppsSettings` lines 554–596, `MyAppRow` lines 628–661)

**Interfaces:**
- Consumes: `addFromPanel`, `addTyped`, `append`, `remove`, `MyAppRow.installed(_:)` (all unchanged).
- Produces: nothing new.

- [ ] **Step 1: Replace `MyAppsSettings`' doc comment and `body`:**

```swift
/// R51, R95: the apps that count as yours beyond the ones Locant finds, one row each with Remove
/// trailing, like Grant… and Choose… elsewhere; a second group adds one by picking an .app on this
/// Mac or by typing a bundle id.
struct MyAppsSettings: View {
    @Environment(AppState.self) private var state
    @State private var typed = ""

    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            Section {
                if preferences.myApps.isEmpty {
                    Text("Locant finds apps you build on its own. Add any it misses.")
                        .foregroundStyle(.secondary)
                }
                ForEach(preferences.myApps, id: \.self) { bundleId in
                    MyAppRow(bundleId: bundleId) { remove(bundleId, from: preferences) }
                }
            }
            Section {
                LabeledContent("Add an app") {
                    Button("Choose…") { addFromPanel(preferences) }
                }
                LabeledContent("Add a bundle ID") {
                    HStack(spacing: 8) {
                        TextField("", text: $typed, prompt: Text("com.example.app"))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addTyped(preferences) }
                        Button("Add") { addTyped(preferences) }
                            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
```

- [ ] **Step 2: Replace `MyAppRow`'s doc comment and `body`** (keep `installed(_:)`):

```swift
/// One app in My Apps: its icon and name, or its bundle id and a plain app icon when it is not on
/// this Mac (a Simulator-only app, say).
private struct MyAppRow: View {
    let bundleId: String
    let remove: () -> Void

    var body: some View {
        let installed = Self.installed(bundleId)
        LabeledContent {
            Button("Remove", action: remove)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: installed?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
                    .resizable()
                    .frame(width: 24, height: 24)
                Text(installed?.name ?? bundleId)
            }
        }
    }
```

- [ ] **Step 3: Build.** Build command → exit 0.

- [ ] **Step 4: Commit.** `git commit -am "settings: My Apps is the list and two ways to add"`

---

### Task 7: Agents tab (R96), and the last footnote goes (R91)

**Files:**
- Modify: `Locant/App/SettingsView.swift` (`AgentSettings` lines 663–749, `AgentRow` lines 751–806, `Footnote` lines 97–104)
- Modify: `Locant/MCP/AgentConfig.swift:38-45` (delete `Agent.detail`)

**Interfaces:**
- Consumes: `AgentRow.connectedGreen` (Task 4), `AgentConnector`, `AgentConfig.jsonSnippet(executable:)`, `ConflictNote`.
- Produces: nothing new.

- [ ] **Step 1: Replace `AgentSettings`' doc comment and `body`** (keep `refresh()` and `act(_:connect:)`):

```swift
/// v0.7.1 R56, R96: paste first; then one row per agent, its state re-read while the window is
/// open, Connect or Disconnect trailing; then the snippet for any other client. The writes run off
/// the main actor: the CLIs take a second.
struct AgentSettings: View {
```

```swift
    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            // v0.8.1 R63, specs/handoff.md R84: paste is the handoff, so it comes first; MCP below is how an agent looks back.
            Section {
                Toggle("Paste into your agent", isOn: $preferences.pastesIntoAgent)
                    .toggleStyle(.switch)
            }
            Section("MCP") {
                ForEach(Agent.allCases) { agent in
                    AgentRow(
                        agent: agent,
                        status: statuses[agent],
                        executable: executable,
                        busy: busy.contains(agent),
                        failure: failures[agent],
                        connect: { act(agent, connect: true) },
                        disconnect: { act(agent, connect: false) }
                    )
                }
            }
            Section {
                LabeledContent("Other agents") {
                    Button(copied ? "Copied" : "Copy Config") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AgentConfig.jsonSnippet(executable: executable), forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
```

- [ ] **Step 2: Replace `AgentRow.body`, and delete `connected(_:)` and `stateText(_:)`** (keep the properties and `connectedGreen`):

```swift
    var body: some View {
        // The state is one row of plain views, rebuilt as a whole on each change: a disabled
        // container left the text invisible after the buttons swapped (Sep 15, 2026). R96: not
        // connected is not a problem, so it is Connect alone.
        LabeledContent {
            HStack(spacing: 8) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working…")
                        .foregroundStyle(.secondary)
                } else if let status {
                    switch status {
                    case .notConnected:
                        Button("Connect", action: connect)
                    case .connected(let found) where found == executable:
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Self.connectedGreen)
                        Text("Connected")
                            .foregroundStyle(.secondary)
                        Button("Disconnect", action: disconnect)
                    case .connected:
                        Image(systemName: "exclamationmark.circle.fill")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.orange)
                        Text("Connected to another copy")
                            .foregroundStyle(.secondary)
                        Button("Reconnect", action: connect)
                        Button("Disconnect", action: disconnect)
                    }
                }
            }
            .id(busy)
        } label: {
            Text(agent.title)
            if let failure { ConflictNote(text: failure) }
        }
    }
```

- [ ] **Step 3: Delete `Agent.detail`** (`AgentConfig.swift`, the doc comment `/// What the row says beneath the name.` and the whole `var detail: String { … }`), and delete the `Footnote` struct from `SettingsView.swift`. Check nothing still uses them: `grep -rn "Footnote(\|\.detail\b" Locant | grep -v HelpView` → no output.

- [ ] **Step 4: Build.** Build command → exit 0.

- [ ] **Step 5: Commit.** `git commit -am "settings: Agents is Connect or Connected, and no footnotes are left"`

---

### Task 8: The menu bar menu (R97)

**Files:**
- Modify: `Locant/App/LocantApp.swift:56-109` (`StatusMenu`)

**Interfaces:**
- Consumes: `state.beginCapture()`, `beginAction(_:)`, `beginColorPick()`, `showBeforeAfter()`, `openCaptureFolder()`, `showHelp()`.
- Produces: nothing new.

- [ ] **Step 1: Replace `StatusMenu`** (the `keyboardShortcut` extension below it stays):

```swift
/// R97: the five actions, then what they leave behind, then Settings and Help, then Quit. v0.4 Show
/// Before & After (R44); iterations are collected by themselves since v0.6 R52.
private struct StatusMenu: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Hotkeys show as the menu's own key equivalents, grey and right-aligned like ⌘, and ⌘Q.
        // A double-tap has no key equivalent, so it stays in the title only when it is all Point has.
        Button(pointTitle) {
            state.beginCapture()
        }
        .keyboardShortcut(pointShortcut)
        Button("Snap") { state.beginAction(.snap) }
            .keyboardShortcut(shortcut("snap"))
        Button("Text") { state.beginAction(.text) }
            .keyboardShortcut(shortcut("text"))
        Button("Color") { state.beginColorPick() }
            .keyboardShortcut(shortcut("color"))
        Button("Cut") { state.beginAction(.cut) }
            .keyboardShortcut(shortcut("cut"))
        Divider()
        Button("Show Before & After") { state.showBeforeAfter() }
        Button("Open Capture Folder") {
            state.openCaptureFolder()
        }
        Divider()
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Locant Help") { state.showHelp() }
        Divider()
        Button("Quit Locant") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// The capture hotkey when it is a chord, else Point's action hotkey (⌃⌥1 by default).
    private var pointShortcut: KeyboardShortcut? {
        state.preferences.hotkey.keyboardShortcut ?? state.preferences.actionHotkeys["point"]?.keyboardShortcut
    }

    /// "Point", or "Point (⌃⌃)" when the only hotkey is a double-tap.
    private var pointTitle: String {
        guard pointShortcut == nil else { return "Point" }
        return "Point (\(state.preferences.hotkey.symbol))"
    }

    private func shortcut(_ action: String) -> KeyboardShortcut? {
        state.preferences.actionHotkeys[action]?.keyboardShortcut
    }
}
```

- [ ] **Step 2: Build.** Build command → exit 0.

- [ ] **Step 3: Commit.** `git commit -am "menu: Point, the actions together, Locant Help"`

---

### Task 9: The help page (R98)

**Files:**
- Modify: `Locant/App/HelpView.swift:4-110`

**Interfaces:**
- Consumes: `state.preferences.hotkey`, `actionHotkeys`, `state.tryPoint()`, `SettingsTab.general`, `.agents`.
- Produces: `HelpView.preferredHeight(for:)` keeps its signature (used by `body`).

- [ ] **Step 1: Replace the doc comment, `preferredHeight`, and `body`** (`goToSettings`, `Row`, its extension, and `HelpWindow` stay):

```swift
/// v0.5 R43, R98: the one page that shows the whole product at once, a short line per row. Opens
/// once after the permission alerts, and any time from Locant Help in the menu bar. A standard
/// window in the Settings idiom (grouped rows, system type, no art): read it, close it, nothing to
/// click through.
struct HelpView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings
    var close: () -> Void = {}
    /// R98: the page's own height, measured; the Form scrolls on a display shorter than that.
    static let contentHeight: CGFloat = 760

    static func preferredHeight(for screen: NSScreen?) -> CGFloat {
        min(contentHeight, (screen?.visibleFrame.height ?? 900) - 60)
    }

    var body: some View {
        let preferences = state.preferences
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 28))
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Point at anything.")
                                .font(.title3.weight(.semibold))
                            Text("Locant hands your coding agent the element under your cursor, so it finds the right code.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Point") {
                    Row(symbol: "keyboard", title: "Open the overlay", detail: "Press the hotkey or click the ball.", key: preferences.hotkey.symbol)
                    Row(symbol: "cursorarrow.rays", title: "Pick the element", detail: "Click it, or drag a frame. ⌥ steps to the parent.", key: "↩")
                    Row(symbol: "text.cursor", title: "Say what should change", detail: "Type a note, press Return, and paste into your agent.", key: "↩")
                    Row(symbol: "plus.square.on.square", title: "Select more than one", detail: "⇧-click to add elements, from any app.", key: "⇧ click")
                }
                Section("The other actions") {
                    Row(symbol: "camera.viewfinder", title: "Snap", detail: "A window, element, or frame as an image.", key: preferences.actionHotkeys["snap"]?.symbol)
                    Row(symbol: "text.viewfinder", title: "Text", detail: "The text in an element or frame.", key: preferences.actionHotkeys["text"]?.symbol)
                    Row(symbol: "eyedropper", title: "Color", detail: "The color under the cursor.", key: preferences.actionHotkeys["color"]?.symbol)
                    Row(symbol: "person.and.background.dotted", title: "Cut", detail: "The subject without its background.", key: preferences.actionHotkeys["cut"]?.symbol)
                    Row(symbol: "circle.circle", title: "The ring", detail: "Hold the ball, release on an action.", key: nil)
                }
                Section("Your agent") {
                    Row(symbol: "terminal", title: "Let your agent fetch captures", detail: "Connect Claude Code, Cursor, or Codex.") {
                        Button("Agents…") { goToSettings(.agents) }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text("Open this again from the menu bar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Settings…") { goToSettings(.general) }
                // The page's one action: the first capture should happen now, over whatever is on
                // screen, not after reading. The page closes first; Locant never appears in its own captures.
                Button("Try it now") {
                    close()
                    state.tryPoint()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 560, height: Self.preferredHeight(for: NSScreen.main))
    }
```

- [ ] **Step 2: Build.** Build command → exit 0.

- [ ] **Step 3: Measure the page and set `contentHeight`.** Create a temporary `LocantTests/HelpHeightProbe.swift`:

```swift
import AppKit
import SwiftUI
import XCTest
@testable import Locant

/// TEMPORARY (deleted before commit): prints the help page's content height.
@MainActor
final class HelpHeightProbe: XCTestCase {
    func testMeasure() async throws {
        let state = AppState()
        let hosting = NSHostingView(rootView: HelpView().frame(width: 560, height: 1400).environment(state))
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 560, height: 1400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        try await Task.sleep(for: .seconds(1))
        func scrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap(scrollView(in:)).first
        }
        let scroll = try XCTUnwrap(scrollView(in: hosting))
        let sections = scroll.documentView?.subviews.first?.subviews ?? []
        let form = (sections.map(\.frame.maxY).max() ?? 0) + (sections.map(\.frame.minY).min() ?? 0)
        let footer = hosting.frame.height - scroll.frame.height
        print("HELP-HEIGHT form \(form) footer \(footer) total \(form + footer)")
        window.close()
    }
}
```

Run: `xcodebuild … test -only-testing:LocantTests/HelpHeightProbe 2>&1 | grep HELP-HEIGHT`. Set `contentHeight` to the printed total rounded up to a whole point. Delete the probe file: `rm LocantTests/HelpHeightProbe.swift`.

- [ ] **Step 4: Build.** Build command → exit 0.

- [ ] **Step 5: Commit.** `git commit -am "help: one short line per row, no settings, as tall as its content"` (check `git status` shows no `HelpHeightProbe.swift`).

---

### Task 10: Alerts and comments (R99, R100)

**Files:**
- Modify: `Locant/App/AppState.swift:347,356,365,375,386-393,567,572,1188`
- Modify: `Locant/Store/Diagnostics.swift:3`

**Interfaces:**
- Consumes/Produces: `inform(_ message: String, detail: String = "")` (private; the default is new).

- [ ] **Step 1: Alerts.** In `checkForUpdates(manual:)`:

```swift
            if manual { inform("Locant could not reach GitHub.", detail: "Try again later.") }
```

```swift
            if manual { inform("Locant \(current) is up to date.") }
```

In `offerUpdate(_:current:)`:

```swift
        alert.informativeText = "You have \(current). Drag the new copy over the old one in Applications; your permissions carry over."
```

`inform`'s signature: `private func inform(_ message: String, detail: String = "") {`.

- [ ] **Step 2: Comments.** Replace, exactly:
  - `/// The daily check, or Settings › General "Check Now…" (`manual`), which ignores the daily` → `/// The daily check, or Settings › General "Check Now" (`manual`), which ignores the daily`
  - `/// v0.8.1 R61: turning Trackpad taps on plays one tap, the other half of the same idea.` → `/// v0.8.1 R61: turning Haptic feedback on plays one tap, the other half of the same idea.`
  - `/// Settings › General "Locant Help": the same page, any time.` → `/// Locant Help in the menu bar (R97): the same page, any time.`
  - `/// The block Settings › General › Copy Diagnostics puts on the clipboard. Gathers the values;` → `/// The block Settings › General › Diagnostics puts on the clipboard. Gathers the values;`
  - In `Diagnostics.swift`: `/// v0.9 R70: the block Settings › General › Copy Diagnostics puts on the clipboard, for pasting` → `/// v0.9 R70: the block Settings › General › Diagnostics puts on the clipboard, for pasting`

- [ ] **Step 3: Build.** Build command → exit 0.

- [ ] **Step 4: Commit.** `git commit -am "updates: the alerts say less"`

---

### Task 11: Docs (R100)

**Files:**
- Modify: `README.md:58-60,202,208`, `CONTRIBUTING.md:11`, `.github/ISSUE_TEMPLATE/bug.yml:25`, `.github/ISSUE_TEMPLATE/tester.yml:14`, `docs/rc-checklist.md:8,9,20`, `CHANGELOG.md` (new section after the intro paragraph)

- [ ] **Step 1: README.** Line 58–59: `Close it; reopen it\n   any time from Settings › General.` → `Close it; reopen it\n   any time from Locant Help in the menu bar.` Line 202: `**Show before & after** in the menu bar` → `**Show Before & After** in the menu bar`, and `Switch: Settings › Captures › Collect iterations.` → `Switch: Settings › Captures › Recapture when your app changes.` Line 208: `Settings › General › Copy Diagnostics puts one block` → `Settings › General › Diagnostics puts one block`.

- [ ] **Step 2: CONTRIBUTING line 11:** `Paste the block from Settings › General › Copy Diagnostics;` → `Paste the block from Settings › General › Diagnostics (Copy);`

- [ ] **Step 3: Issue forms.** `bug.yml` line 25 and `tester.yml` line 14: `Settings › General › Copy Diagnostics, then paste.` → `Settings › General › Diagnostics › Copy (Copy Diagnostics in 0.9.2 and earlier), then paste.`

- [ ] **Step 4: rc-checklist.** Line 8: `after that, Settings › General shows both as granted.` → `after that, Settings › General shows no permission rows.` Line 9: `Settings › General › Locant Help › Show… brings it back.` → `Locant Help in the menu bar brings it back.` Line 20: `| 14 | Settings › General › Check Now…, then Copy Diagnostics; paste it somewhere. |` → `| 14 | Settings › General › Check Now, then Copy beside Diagnostics; paste it somewhere. |`

- [ ] **Step 5: CHANGELOG.** After the intro paragraph, before `## 0.9.2 (2026-10-01)`:

```markdown
## Unreleased

- **Settings say less.** Every row is a title and a control: the descriptions and footnotes are gone, the permissions show only when one is missing, and an agent that is not connected shows just Connect. Point's two hotkeys share one row, and Clear appears only while you record a key (⌫ clears too). Renamed: Trackpad taps is Haptic feedback, Collect iterations is Recapture when your app changes, Keep images is Keep captures. In the menu bar, Capture is Point and Locant Help opens the help page, now one short line per row.
```

- [ ] **Step 6: Check.** `grep -rn "Copy Diagnostics\|Collect iterations\|Trackpad taps\|Locant Help › Show" README.md CONTRIBUTING.md .github docs/rc-checklist.md` → only the "(Copy Diagnostics in 0.9.2 and earlier)" lines.

- [ ] **Step 7: Commit.** `git add -A README.md CONTRIBUTING.md CHANGELOG.md .github docs/rc-checklist.md && git commit -m "docs: the new Settings labels and places"`

---

### Task 12: Verify on screen

**Files:** none committed. Scratch: `$S=/private/tmp/claude-501/-Users-malik-Documents-Locant--claude-worktrees-settings-simplification-084f77/e2eb2731-336f-4a78-a5b6-fcddc5cde6c2/scratchpad`.

- [ ] **Step 1: Every test.** `xcodebuild … test 2>&1 | grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -2` → `** TEST SUCCEEDED **`, 0 failures.

- [ ] **Step 2: Save the defaults, and write the helper.** `defaults export com.malikzhang.deixis $S/defaults-before.plist`. Write `$S/tools/win.swift` (run with `swift $S/tools/win.swift …`; the shell is Accessibility-trusted and may record the screen):

```swift
// win <pid> <window title> [width height]: activates the app, makes the window key (optionally
// resizing it), and prints its CGWindowID. win <pid> <window title> press <button title>: AXPress.
import AppKit
import ApplicationServices

let args = CommandLine.arguments
let pid = pid_t(args[1])!
let title = args[2]
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}
func button(in element: AXUIElement, titled wanted: String) -> AXUIElement? {
    if attribute(element, kAXRoleAttribute) as? String == kAXButtonRole,
       attribute(element, kAXTitleAttribute) as? String == wanted || attribute(element, kAXDescriptionAttribute) as? String == wanted {
        return element
    }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let found = button(in: child, titled: wanted) { return found }
    }
    return nil
}
NSRunningApplication(processIdentifier: pid)?.activate()
let windows = attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
guard let window = windows.first(where: { attribute($0, kAXTitleAttribute) as? String == title }) else {
    print("no window titled \(title)")
    exit(1)
}
if args.count == 5, args[3] == "press" {
    guard let target = button(in: window, titled: args[4]) else { print("no button \(args[4])"); exit(1) }
    AXUIElementPerformAction(target, kAXPressAction as CFString)
    exit(0)
}
if args.count == 5, let width = Double(args[3]), let height = Double(args[4]) {
    var size = CGSize(width: width, height: height)
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
}
AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
AXUIElementPerformAction(window, kAXRaiseAction as CFString)
Thread.sleep(forTimeInterval: 0.6)
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for info in list where info[kCGWindowOwnerPID as String] as? pid_t == pid && info[kCGWindowName as String] as? String == title {
    print(info[kCGWindowNumber as String] as? Int ?? 0)
    print(attribute(window, kAXSizeAttribute).map { "\($0)" } ?? "")
}
```

- [ ] **Step 3: Launch the scratch build beside the user's copy, silent and without a ball:** `open -n "$DD/Build/Products/Debug/Locant.app" --args -ballEnabled '<false/>' -checksForUpdates '<false/>' -collectsIterations '<false/>' -sounds '<false/>' -trackpadTaps '<false/>'`; its pid: `pgrep -f "$DD/Build/Products/Debug/Locant.app/Contents/MacOS/Locant -ballEnabled"`.

- [ ] **Step 4: Capture each Settings tab, dark.** Open Settings through System Events on that pid (`menu bar item 1 of menu bar 2` → `menu item "Settings…"`), click each toolbar tab, make the window key with `swift $S/tools/win.swift <pid> <tab>` (it prints the CGWindowID), and `screencapture -x -o -l <id> $S/shots/<tab>-dark.png`. Read each image: no row on two lines; Point's two recorders on one row; Agents shows Connect or Connected; no Granted rows.

- [ ] **Step 5: Recording state.** `swift $S/tools/win.swift <pid> Hotkeys press ⌃⌥2`, capture Hotkeys (Clear shows before "Press keys…"), then `… press "Press keys…"` to stop. No key is pressed, so no hotkey is written.

- [ ] **Step 6: Minimum width.** Note the window's size (the helper prints it), set it with `swift $S/tools/win.swift <pid> Hotkeys 480 <height>`, capture Hotkeys, General, and My Apps, then put the size back.

- [ ] **Step 7: Help and menu.** Click `menu item "Locant Help"`, capture the "Locant Help" window (no scroll bar, no empty band at the bottom). Open the menu bar item and capture the menu with `screencapture -x -R` around it; press Esc through System Events.

- [ ] **Step 8: Light.** Quit the scratch build (`kill <pid>`, poll up to 15 s), relaunch with `-NSRequiresAquaSystemAppearance YES` added, repeat Step 4 into `*-light.png`.

- [ ] **Step 9: A missing permission.** Temporarily change `if !accessibilityGranted || !screenRecordingGranted {` to `if true {` and `if !screenRecordingGranted {` to `if true {`, build, launch, capture General, then `git checkout Locant/App/SettingsView.swift` and build again. `git status` is clean.

- [ ] **Step 10: Clean up.** Quit the scratch build; `defaults export com.malikzhang.deixis $S/defaults-after.plist`; `diff <(plutil -p $S/defaults-before.plist) <(plutil -p $S/defaults-after.plist)` shows at most the Settings window frame and `lastUpdateCheck`. Restore the Settings window frame from the before file if it changed.

- [ ] **Step 11: Show the user** the dark and light shots of every tab, the recording state, the help page, and the menu.
