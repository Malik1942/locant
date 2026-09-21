import AppKit
import SwiftUI

/// v0.3 R19: the one place Locant is a window. PRD §6.3 "Settings": grouped forms, system
/// controls at default sizes, footnotes under rows, nothing custom. Resizable from 480×360;
/// every tab is a grouped Form that reflows with the width.
struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        // v0.6 R51: tabs, the way System Settings groups things. General is what the app is
        // and needs; Hotkeys is every key; Captures is what is written and how; My Apps is the list;
        // Agents (v0.7.1 R56, v0.8.1 R63) is where Return pastes and who fetches captures over MCP. The selection lives in AppState so
        // the help page can open Settings on the tab a row belongs to.
        TabView(selection: $state.settingsTab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            HotkeySettings()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
                .tag(SettingsTab.hotkeys)
            CaptureSettings()
                .tabItem { Label("Captures", systemImage: "photo.on.rectangle") }
                .tag(SettingsTab.captures)
            MyAppsSettings()
                .tabItem { Label("My Apps", systemImage: "app.badge.checkmark") }
                .tag(SettingsTab.myApps)
            AgentSettings()
                .tabItem { Label("Agents", systemImage: "terminal") }
                .tag(SettingsTab.agents)
        }
        .frame(minWidth: 480, idealWidth: 520, maxWidth: .infinity, minHeight: 360, idealHeight: 560, maxHeight: .infinity)
        .background(SettingsWindowConfigurator())
    }
}

/// The `Settings` scene builds its window without a minimize button. This reaches the window
/// once the view is in it and adds one; the scene itself remembers the frame. It also grows a
/// restored window that is shorter than the tab it opens on, so every row shows without scrolling.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguratorView { ConfiguratorView() }
    func updateNSView(_ view: ConfiguratorView, context: Context) {}

    final class ConfiguratorView: NSView {
        private var configured: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== configured else { return }
            configured = window
            window.styleMask.insert([.miniaturizable, .resizable])
            // The form lays out over a few runloop turns after the frame is restored; check more
            // than once, growing only, so the first short measurement is not the last word.
            for delay in [0, 150, 400] {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak window] in
                    guard let window else { return }
                    Self.growToFitContent(window)
                }
            }
        }

        /// Adds the height the open tab's form needs beyond what the window shows, keeping the top
        /// edge in place and the window on its screen. Never shrinks.
        private static func growToFitContent(_ window: NSWindow) {
            guard let content = window.contentView else { return }
            // The scroll view runs under the toolbar; what the form can use is the layout rect.
            let shortfall = formHeight(in: content) - window.contentLayoutRect.height
            guard shortfall > 0 else { return }
            var frame = window.frame
            frame.size.height += shortfall
            frame.origin.y -= shortfall
            if let screen = window.screen ?? NSScreen.main {
                let bounds = screen.visibleFrame
                frame.size.height = min(frame.height, bounds.height)
                frame.origin.y = max(frame.origin.y, bounds.minY)
            }
            window.setFrame(frame, display: true, animate: false)
        }

        /// The height the open tab's grouped Form wants. The document view is stretched to fill the
        /// clip, so it is measured from its sections: the last one's far edge plus the inset the
        /// first one has from the near edge, which the Form mirrors at the bottom.
        private static func formHeight(in view: NSView) -> CGFloat {
            if let scroll = view as? NSScrollView, let document = scroll.documentView {
                let sections = document.subviews.first?.subviews ?? []
                if let far = sections.map(\.frame.maxY).max(), let near = sections.map(\.frame.minY).min() {
                    return far + near
                }
                return document.frame.height
            }
            return view.subviews.map(formHeight(in:)).max() ?? 0
        }
    }
}

private struct Footnote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// A permission as System Settings would show it: the state at a glance, and a way to grant it when missing.
private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let grant: () -> Void

    /// Apple's macOS system green as the light appearance draws it (#28CD41). The dark appearance
    /// lightens its green by design, and on a 13 pt tick that read as pale and washed out
    /// (Malik, Sep 14 2026), so the light value is pinned in both appearances. Measured in the dark
    /// grouped Form: `.green` renders P3 #68CE67, this renders #63CA56, same lightness, more chroma.
    fileprivate static let grantedGreen = Color(red: 0x28 / 255.0, green: 0xCD / 255.0, blue: 0x41 / 255.0)

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(granted ? Self.grantedGreen : .orange)
                Text(granted ? "Granted" : "Not granted")
                    .foregroundStyle(.secondary)
                if !granted {
                    Button("Grant…", action: grant)
                }
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

/// Under a hotkey row: the system's warning triangle and what clashes. Never blocks.
private struct ConflictNote: View {
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

struct GeneralSettings: View {
    @Environment(AppState.self) private var state
    /// The two grants Locant needs, re-read while the window is open so a change in System Settings shows at once.
    @State private var accessibilityGranted = AccessibilityReader.isTrusted(prompt: false)
    @State private var screenRecordingGranted = ScreenCapture.hasPermission()
    /// Check Now… in flight; the button waits for the answer.
    @State private var checking = false

    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            Section {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Reads what is under your cursor and listens for the hotkey.",
                    granted: accessibilityGranted
                ) {
                    _ = AccessibilityReader.isTrusted(prompt: true)
                    openPrivacyPane("Privacy_Accessibility")
                }
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Captures the pixels of the element.",
                    granted: screenRecordingGranted
                ) {
                    _ = ScreenCapture.requestPermission()
                    openPrivacyPane("Privacy_ScreenCapture")
                }
                if !accessibilityGranted || !screenRecordingGranted {
                    Footnote(text: "macOS ties each grant to the app's signature. After an update, or if a switch is on but Locant still cannot capture, remove Locant from the list and add /Applications/Locant.app again.")
                }
            }
            Section {
                Toggle(isOn: $preferences.ballEnabled) {
                    Text("Floating ball")
                    Text("A quiet disc that wakes when you approach. Click it to point, hold for the ring. The hotkey works either way.")
                }
                .toggleStyle(.switch)
                Toggle(isOn: $preferences.ballAutoHide) {
                    Text("Auto-hide")
                    Text("After 2 seconds without use, the ball tucks into the nearest screen edge with part of it showing. Move toward it to bring it back.")
                }
                .toggleStyle(.switch)
                .disabled(!preferences.ballEnabled)
            }
            Section {
                Toggle(isOn: $preferences.trackpadTaps) {
                    Text("Trackpad taps")
                    Text("A light tap under your finger when the outline moves to a new element, when the ring opens and between its segments, and when a capture lands. Needs a Force Touch trackpad.")
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
            Section {
                Toggle(isOn: $preferences.checksForUpdates) {
                    Text("Check for updates")
                    Text("Once a day, Locant asks GitHub for the newest release. The request carries the version number and nothing about you or your captures.")
                }
                .toggleStyle(.switch)
                LabeledContent {
                    Button("Check Now…") {
                        checking = true
                        Task {
                            await state.checkForUpdates(manual: true)
                            checking = false
                        }
                    }
                    .disabled(checking)
                } label: {
                    Text("Version \(UpdateCheck.currentVersion?.description ?? "unknown")")
                    if let lastCheck = preferences.lastUpdateCheck {
                        Text("Last checked \(lastCheck.formatted(.relative(presentation: .named))).")
                    } else {
                        Text("Not checked yet.")
                    }
                }
            }
            Section {
                LabeledContent {
                    Button("Show…") { state.showHelp() }
                } label: {
                    Text("Locant Help")
                    Text("The one-page guide shown on first launch: every action, its hotkey, and the gestures on the overlay.")
                }
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshPermissions() {
        accessibilityGranted = AccessibilityReader.isTrusted(prompt: false)
        screenRecordingGranted = ScreenCapture.hasPermission()
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// R51: the capture hotkey and the five action hotkeys, with their clashes, on one tab.
struct HotkeySettings: View {
    @Environment(AppState.self) private var state
    /// R29: a warning under each hotkey row, by action name ("capture" for the capture hotkey).
    @State private var conflicts: [String: String] = [:]

    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            Section {
                // System Settings row: title and description in the label, the control trailing.
                LabeledContent {
                    HotkeyRecorder(
                        hotkey: Binding(get: { preferences.hotkey }, set: { preferences.hotkey = $0 ?? .default }),
                        fallback: .default,
                        rejects: { rejection(for: $0, action: "capture") },
                        onBegin: { state.pauseHotkey() }, onEnd: { state.resumeHotkey() }
                    )
                } label: {
                    Text("Capture hotkey")
                    Text("Press a key with modifiers, or double-tap one modifier. Double-tap Command is used by Codex; double-tap Option by Claude Desktop.")
                    if let warning = conflicts["capture"] { ConflictNote(text: warning) }
                }
            }
            Section {
                ForEach(Preferences.hotkeyActions, id: \.self) { action in
                    LabeledContent {
                        HotkeyRecorder(
                            hotkey: Binding(get: { preferences.actionHotkeys[action] }, set: { preferences.setActionHotkey($0, for: action) }),
                            fallback: Preferences.defaultActionHotkey(action),
                            clearable: true,
                            rejects: { rejection(for: $0, action: action) },
                            onBegin: { state.pauseHotkey() }, onEnd: { state.resumeHotkey() }
                        )
                    } label: {
                        Text(action.capitalized)
                        if let warning = conflicts[action] { ConflictNote(text: warning) }
                    }
                }
                Footnote(text: "Control-Option and the action's number, in menu order; the ring shows each number. Point also answers to the capture hotkey above. Snap, Text, Color, and Cut are on the ball too: press and hold it.")
            }
        }
        .formStyle(.grouped)
        .task { refreshConflicts() }
        .onChange(of: preferences.hotkey) { refreshConflicts() }
        .onChange(of: preferences.actionHotkeys) { refreshConflicts() }
    }

    /// The clash inside Locant that the recorder refuses; a clash with macOS is only shown afterwards.
    private func rejection(for hotkey: Hotkey, action: String) -> String? {
        state.preferences.action(using: hotkey, excluding: action).map { HotkeyConflict.locant(action: $0).message }
    }

    private func refreshConflicts() {
        let preferences = state.preferences
        var found: [String: String] = [:]
        found["capture"] = HotkeyConflicts.check(preferences.hotkey, for: "capture", in: preferences).first?.message
        for action in Preferences.hotkeyActions {
            guard let hotkey = preferences.actionHotkeys[action] else { continue }
            found[action] = HotkeyConflicts.check(hotkey, for: action, in: preferences).first?.message
        }
        conflicts = found
    }
}

/// R51: where captures go and how they are kept, iterations (R52), the selection handles, and the Color format.
struct CaptureSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            Section {
                LabeledContent("Capture folder") {
                    HStack {
                        TextField("", text: .constant(preferences.captureFolder))
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)
                        Button("Choose…") { chooseFolder(preferences) }
                    }
                }
                Picker("Organize captures", selection: $preferences.organization) {
                    ForEach(CaptureOrganization.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                Picker("Keep images", selection: $preferences.retentionDays) {
                    ForEach(Preferences.retentionChoices, id: \.self) { days in
                        Text(days == 0 ? "Forever" : "\(days) days").tag(days)
                    }
                }
                .pickerStyle(.menu)
                Footnote(text: "Each capture writes a PNG and a JSON sidecar here. Finder tags are always added: Locant, the app, fix or reference, and the project when known. Older images go to the Trash; captures an agent marked resolved stay.")
            }
            Section {
                Toggle(isOn: $preferences.collectsIterations) {
                    Text("Collect iterations")
                    Text("After you point at an element in an app you build, each time that app launches or comes to the front within a day, Locant captures the element again and keeps the git diff, when it looks different. See them with Show before & after in the menu bar.")
                }
                .toggleStyle(.switch)
            }
            Section {
                Toggle(isOn: $preferences.adjustSelection) {
                    Text("Adjust selection before capturing")
                    Text("After you drag a region for Snap, Text, or Cut, handles let you fine-tune it. Press Return to capture, Esc to cancel.")
                }
                .toggleStyle(.switch)
            }
            Section {
                Picker("Color format", selection: $preferences.colorFormat) {
                    ForEach(ColorFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("Color space", selection: $preferences.colorSpace) {
                    ForEach(ColorSpaceChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Footnote(text: "The Color action copies the pixel under the cursor in this format.")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder(_ preferences: Preferences) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = preferences.captureFolderURL
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            preferences.captureFolder = url.path(percentEncoded: false)
        }
    }
}

/// Records the next key press or modifier double-tap as the hotkey. Esc cancels.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey?
    /// What "Reset" restores.
    var fallback: Hotkey? = nil
    /// Whether the action may be left without a hotkey ("Clear"); implied when there is no fallback.
    var clearable = false
    /// A reason to refuse what was just pressed (shown in the button, recording goes on), or nil to take it.
    var rejects: (Hotkey) -> String? = { _ in nil }
    let onBegin: () -> Void
    let onEnd: () -> Void

    @State private var recording = false
    @State private var hint: String?
    @State private var monitor: Any?
    @State private var lastTap: (modifier: HotkeyModifier, time: TimeInterval)?
    @State private var modifiersWereDown = false

    private static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
    ]
    private static let specialKeys: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    var body: some View {
        // The width sits on the label so the bordered button itself is the fixed-width control;
        // a frame on the button would leave invisible space around a short title.
        HStack(spacing: 8) {
            if !recording {
                if let fallback, hotkey != fallback {
                    Button("Reset") { hotkey = fallback }
                }
                if hotkey != nil, clearable || fallback == nil {
                    Button("Clear") { hotkey = nil }
                }
            }
            Button {
                recording ? stop() : begin()
            } label: {
                Text(recording ? (hint ?? "Press keys…") : (hotkey?.title ?? "None"))
                    .lineLimit(1)
                    .frame(minWidth: 150)
            }
        }
        .fixedSize()
    }

    private func begin() {
        onBegin()
        recording = true
        hint = nil
        lastTap = nil
        modifiersWereDown = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let type = event.type, keyCode = event.keyCode, flags = event.modifierFlags
            let chars = event.type == .keyDown ? event.charactersIgnoringModifiers : nil
            let timestamp = event.timestamp
            MainActor.assumeIsolated { handle(type: type, keyCode: keyCode, flags: flags, characters: chars, timestamp: timestamp) }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        hint = nil
        onEnd()
    }

    private func handle(type: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?, timestamp: TimeInterval) {
        switch type {
        case .keyDown:
            if keyCode == 53 { stop(); return } // Esc
            let modifiers = KeyModifiers(flags)
            let name: String
            if let fn = Self.functionKeys[keyCode] {
                name = fn
            } else if let special = Self.specialKeys[keyCode] {
                name = special
            } else {
                name = (characters ?? "").uppercased()
            }
            guard !name.isEmpty else { return }
            if modifiers.isEmpty, Self.functionKeys[keyCode] == nil {
                hint = "Add ⌘, ⌥, ⌃ or ⇧"
                return
            }
            let chord = Hotkey.chord(keyCode: keyCode, modifiers: modifiers, key: name)
            if let reason = rejects(chord) {
                hint = reason
                return
            }
            hotkey = chord
            stop()
        case .flagsChanged:
            let modifiers = KeyModifiers(flags)
            let down = !modifiers.isEmpty
            defer { modifiersWereDown = down }
            guard down, !modifiersWereDown else { return }
            let single: HotkeyModifier? = switch modifiers {
            case [.control]: .control
            case [.option]: .option
            case [.shift]: .shift
            case [.command]: keyCode == 54 ? .rightCommand : .command
            default: nil
            }
            guard let single else { lastTap = nil; return }
            if let last = lastTap, last.modifier == single, timestamp - last.time <= HotkeyMonitor.window {
                let tap = Hotkey.doubleTap(single)
                if let reason = rejects(tap) {
                    hint = reason
                    lastTap = nil
                    return
                }
                hotkey = tap
                stop()
            } else {
                lastTap = (single, timestamp)
                hint = "Again to double-tap \(single.glyph), or add a key"
            }
        default:
            break
        }
    }
}

/// R51: the apps that count as yours, in the grouped idiom of the other tabs. One row per app with
/// its icon, name, and bundle id and Remove trailing, like Grant… and Choose… elsewhere; a second
/// group adds one by picking an .app on this Mac or by typing a bundle id.
struct MyAppsSettings: View {
    @Environment(AppState.self) private var state
    @State private var typed = ""

    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            Section {
                if preferences.myApps.isEmpty {
                    Text("No apps added")
                        .foregroundStyle(.secondary)
                }
                ForEach(preferences.myApps, id: \.self) { bundleId in
                    MyAppRow(bundleId: bundleId) { remove(bundleId, from: preferences) }
                }
                Footnote(text: "Locant already treats apps you build (Simulator, Xcode builds, your signing identity) as yours. Add anything it misses.")
            }
            Section {
                LabeledContent {
                    Button("Choose…") { addFromPanel(preferences) }
                } label: {
                    Text("Add an app")
                    Text("Pick an app on this Mac; its bundle id is added.")
                }
                LabeledContent {
                    HStack(spacing: 8) {
                        TextField("", text: $typed, prompt: Text("com.example.app"))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addTyped(preferences) }
                        Button("Add") { addTyped(preferences) }
                            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } label: {
                    Text("Bundle id")
                    Text("For an app that is not on this Mac, such as one that runs only in the Simulator.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addFromPanel(_ preferences: Preferences) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            append(id, to: preferences)
        }
    }

    private func addTyped(_ preferences: Preferences) {
        let id = typed.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }
        append(id, to: preferences)
        typed = ""
    }

    private func append(_ id: String, to preferences: Preferences) {
        guard !preferences.myApps.contains(id) else { return }
        preferences.myApps.append(id)
    }

    private func remove(_ id: String, from preferences: Preferences) {
        preferences.myApps.removeAll { $0 == id }
    }
}

/// One app in My Apps: the icon and name when the app is on this Mac, the bundle id beneath;
/// only the id, and a plain app icon, when it is not (a Simulator-only app, say).
private struct MyAppRow: View {
    let bundleId: String
    let remove: () -> Void

    var body: some View {
        let installed = Self.installed(bundleId)
        LabeledContent {
            Button("Remove", action: remove)
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: installed?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(installed?.name ?? bundleId)
                    Text(installed == nil ? "Not on this Mac; matched by bundle id." : bundleId)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func installed(_ bundleId: String) -> (name: String, icon: NSImage)? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return (name, NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
    }
}

/// v0.7.1 R56: one row per agent, its state re-read while the window is open, Connect or
/// Disconnect trailing, the way the permission rows read. The writes run off the main actor:
/// the CLIs take a second.
struct AgentSettings: View {
    @State private var statuses: [Agent: AgentStatus] = [:]
    @State private var failures: [Agent: String] = [:]
    @State private var busy: Set<Agent> = []
    @State private var copied = false
    @Environment(AppState.self) private var state

    private var executable: String { AgentConnector.executable }

    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            // v0.8.1 R63: paste is the handoff, so it comes first; MCP below is how an agent looks back.
            Section {
                Toggle(isOn: $preferences.pastesIntoAgent) {
                    Text("Paste into your agent")
                    Text("After Return, Locant brings forward the agent app you used last, Claude, Cursor, or Codex, and pastes the capture into its message field. Locant never sends it; you do.")
                }
                .toggleStyle(.switch)
                Footnote(text: "The note field shows where the capture will go. The clipboard holds it either way, and connected agents can still fetch it.")
            }
            Section {
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
                Footnote(text: "Connect adds one server named locant to the agent's own configuration. It runs \(executable) --mcp when the agent starts, and gives it four tools: the latest capture, a list, one capture by id, and resolve. Nothing runs until then.")
            }
            Section {
                LabeledContent {
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AgentConfig.jsonSnippet(executable: executable), forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                } label: {
                    Text("Any other agent")
                    Text("A JSON snippet for an MCP client that runs stdio servers: Gemini CLI, Windsurf, Zed, Claude Desktop.")
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

    private func refresh() async {
        let found = await Task.detached {
            Dictionary(uniqueKeysWithValues: Agent.allCases.map { ($0, AgentConnector.status($0)) })
        }.value
        statuses = found
    }

    private func act(_ agent: Agent, connect: Bool) {
        busy.insert(agent)
        failures[agent] = nil
        Task {
            do {
                try await Task.detached {
                    if connect { try AgentConnector.connect(agent) } else { try AgentConnector.disconnect(agent) }
                }.value
            } catch {
                failures[agent] = error.localizedDescription
            }
            await refresh()
            busy.remove(agent)
        }
    }
}

private struct AgentRow: View {
    let agent: Agent
    let status: AgentStatus?
    let executable: String
    let busy: Bool
    let failure: String?
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        // The state is one row of plain views, rebuilt as a whole on each change: a disabled
        // container left the text invisible after the buttons swapped (Sep 15, 2026).
        LabeledContent {
            HStack(spacing: 8) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working…")
                        .foregroundStyle(.secondary)
                } else if let status {
                    Image(systemName: connected(status) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(connected(status) ? PermissionRow.grantedGreen : .orange)
                    Text(stateText(status))
                        .foregroundStyle(.secondary)
                    switch status {
                    case .notConnected:
                        Button("Connect", action: connect)
                    case .connected(let found) where found == executable:
                        Button("Disconnect", action: disconnect)
                    case .connected:
                        Button("Reconnect", action: connect)
                        Button("Disconnect", action: disconnect)
                    }
                }
            }
            .id(busy)
        } label: {
            Text(agent.title)
            Text(agent.detail)
            if let failure { ConflictNote(text: failure) }
        }
    }

    private func connected(_ status: AgentStatus) -> Bool {
        if case .connected(let found) = status { return found == executable }
        return false
    }

    private func stateText(_ status: AgentStatus) -> String {
        switch status {
        case .notConnected: "Not connected"
        case .connected(let found): found == executable ? "Connected" : "Connected to another copy"
        }
    }
}
