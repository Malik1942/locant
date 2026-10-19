import AppKit
import SwiftUI

/// v0.3 R19: the one place Locant is a window. PRD §6.3 "Settings": grouped forms, system
/// controls at default sizes, nothing custom. R101: one compact width, and each tab as tall as
/// its rows, the way an Apple app's settings window is.
struct SettingsView: View {
    /// R101: wide enough for Point's two hotkeys beside its title, and no wider.
    static let width: CGFloat = 480

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
        .frame(width: Self.width)
        .frame(minHeight: 120, idealHeight: 420, maxHeight: .infinity)
        .background(SettingsWindowConfigurator(tab: state.settingsTab))
    }
}

/// The `Settings` scene builds its window without a minimize button. This reaches the window
/// once the view is in it and adds one; the scene itself remembers where the window was. R101:
/// it also fits the window's height to the open tab's rows, when the window opens and on each
/// tab change, keeping the top edge in place, so no tab scrolls or ends in empty space.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    let tab: SettingsTab

    func makeNSView(context: Context) -> ConfiguratorView { ConfiguratorView() }

    func updateNSView(_ view: ConfiguratorView, context: Context) {
        view.show(tab)
    }

    final class ConfiguratorView: NSView {
        private var configured: NSWindow?
        private var tab: SettingsTab?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== configured else { return }
            configured = window
            window.styleMask.insert(.miniaturizable)
            window.styleMask.remove(.resizable)
            fitSoon(animate: false)
        }

        func show(_ tab: SettingsTab) {
            guard tab != self.tab else { return }
            let first = self.tab == nil
            self.tab = tab
            if !first { fitSoon(animate: true) }
        }

        /// The form lays out over a few runloop turns after a tab appears; measure more than once,
        /// so the first, unfinished measurement is not the last word.
        private func fitSoon(animate: Bool) {
            for delay in [0, 150, 400] {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak self] in
                    guard let window = self?.window else { return }
                    Self.fitToContent(window, animate: animate)
                }
            }
        }

        /// Makes the window as tall as the open tab's form, keeping the top edge in place and the
        /// window on its screen; a tab taller than the screen scrolls.
        private static func fitToContent(_ window: NSWindow, animate: Bool) {
            guard let content = window.contentView else { return }
            let wanted = formHeight(in: content)
            // The scroll view runs under the toolbar; what the form can use is the layout rect.
            let delta = wanted - window.contentLayoutRect.height
            guard wanted > 0, abs(delta) >= 1 else { return }
            var frame = window.frame
            frame.size.height += delta
            frame.origin.y -= delta
            if let screen = window.screen ?? NSScreen.main {
                let bounds = screen.visibleFrame
                frame.size.height = min(frame.height, bounds.height)
                frame.origin.y = max(frame.origin.y, bounds.minY)
            }
            window.setFrame(frame, display: true, animate: animate)
        }

        /// The height the open tab's grouped Form wants. The document view is stretched to fill the
        /// clip, so it is measured from its sections: the last one's far edge plus the inset the
        /// first one has from the near edge, which the Form mirrors at the bottom. Hidden views are
        /// the other tabs.
        private static func formHeight(in view: NSView) -> CGFloat {
            guard !view.isHidden else { return 0 }
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
    /// Check Now in flight; the button waits for the answer.
    @State private var checking = false
    /// Copy reads "Copied" for two seconds after the click.
    @State private var copiedDiagnostics = false

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

/// Records the next key press or modifier double-tap as the hotkey. Esc cancels. R93: at rest only
/// Reset shows, and only when the key is not the default; Clear shows while recording, and ⌫ or ⌦
/// alone clears too.
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

    private static func installed(_ bundleId: String) -> (name: String, icon: NSImage)? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return (name, NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
    }
}

/// v0.7.1 R56, R96: paste first; then one row per agent, its state re-read while the window is
/// open, Connect or Disconnect trailing; then the snippet for any other client. The writes run off
/// the main actor: the CLIs take a second.
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
    /// Apple's macOS system green as the light appearance draws it (#28CD41). The dark appearance
    /// lightens its green by design, and on a 13 pt tick that read as pale and washed out
    /// (Malik, Sep 14 2026), so the light value is pinned in both appearances. Measured in the dark
    /// grouped Form: `.green` renders P3 #68CE67, this renders #63CA56, same lightness, more chroma.
    private static let connectedGreen = Color(red: 0x28 / 255.0, green: 0xCD / 255.0, blue: 0x41 / 255.0)

    let agent: Agent
    let status: AgentStatus?
    let executable: String
    let busy: Bool
    let failure: String?
    let connect: () -> Void
    let disconnect: () -> Void

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
}
