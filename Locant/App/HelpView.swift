import AppKit
import SwiftUI

/// v0.5 R43: the one page that shows the whole product at once. Opens once after the permission
/// alerts, and any time from Settings › General. A standard window in the
/// Settings idiom (grouped rows, system type, no art): read it, close it, nothing to click through.
struct HelpView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings
    var close: () -> Void = {}
    /// Tall enough for the whole page on a normal display; the Form scrolls on a small one.
    static func preferredHeight(for screen: NSScreen?) -> CGFloat {
        min(900, (screen?.visibleFrame.height ?? 900) - 60)
    }

    var body: some View {
        @Bindable var preferences = state.preferences
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
                            Text("Locant hands your coding agent the element under your cursor: role, identifier, frame, a cropped image, and your note. Paste it and the agent finds the right file.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Point") {
                    Row(symbol: "keyboard", title: "Open the overlay", detail: "Press the hotkey, or click the ball. The pointing hand in the menu bar works too.", key: preferences.hotkey.symbol)
                    Row(symbol: "cursorarrow.rays", title: "Pick the element", detail: "Hover, then click or press Return. Drag for a frame with everything inside it; Option steps to the parent.", key: "↩")
                    Row(symbol: "text.cursor", title: "Say what should change", detail: "Type a note, press Return. The payload is on the clipboard; paste it into your agent. Esc at any point cancels, nothing written.", key: "↩")
                    Row(symbol: "plus.square.on.square", title: "Select more than one", detail: "Hold ⇧ and click to add elements, from any app. Return confirms the set, or click the last one without ⇧; the note covers all of them.", key: "⇧ click")
                    Row(symbol: "circle.dotted", title: "Keep the ball?", detail: "The glass disc at the edge of the screen. The hotkey works without it; change your mind any time in Settings.") {
                        Toggle("Floating ball", isOn: $preferences.ballEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    Row(symbol: "keyboard.badge.ellipsis", title: "Change the hotkeys", detail: "Point and each action can be re-recorded as a chord, or as a double-tap of one modifier.") {
                        Button("Hotkeys…") { goToSettings(.hotkeys) }
                    }
                }
                Section("The other actions") {
                    Row(symbol: "camera.viewfinder", title: "Snap", detail: "The window under the cursor, or a dragged region, as a PNG. Option picks the element under the cursor instead, and again its parent; hold ⌘ at the click to keep it off disk.", key: preferences.actionHotkeys["snap"]?.symbol)
                    Row(symbol: "text.viewfinder", title: "Text", detail: "The text in an element or a region, recognized, to the clipboard.", key: preferences.actionHotkeys["text"]?.symbol)
                    Row(symbol: "eyedropper", title: "Color", detail: "A magnifier follows the cursor. Arrows nudge by a pixel, click copies the value.", key: preferences.actionHotkeys["color"]?.symbol)
                    Row(symbol: "person.and.background.dotted", title: "Cut", detail: "The subject cut onto a transparent background, from the element, the window, or a frame. ⌥ and ⌘ as in Snap.", key: preferences.actionHotkeys["cut"]?.symbol)
                    Row(symbol: "circle.circle", title: "The ring", detail: "All four are on the ball: hold it for half a second and release on one. A shorter press is Point.", key: nil)
                }
                // These rows are the settings themselves, so a reader decides without leaving the page.
                Section("Afterwards") {
                    Row(symbol: "arrow.triangle.2.circlepath", title: "Collect iterations", detail: "Point at an element in an app you build, let your agent edit, run the app again: Locant captures the element again with the git diff whenever it looks different. Show before & after is in the menu bar.") {
                        Toggle("Collect iterations", isOn: $preferences.collectsIterations)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    Row(symbol: "clock.arrow.circlepath", title: "Keep images", detail: "Older images go to the Trash with their sidecars. Captures an agent marked resolved stay.") {
                        Picker("Keep images", selection: $preferences.retentionDays) {
                            ForEach(Preferences.retentionChoices, id: \.self) { days in
                                Text(days == 0 ? "Forever" : "\(days) days").tag(days)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    Row(symbol: "arrow.down.circle", title: "Check for updates", detail: "Once a day Locant asks GitHub whether a newer version exists and tells you. The request carries the version number and nothing else.") {
                        Toggle("Check for updates", isOn: $preferences.checksForUpdates)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    Row(symbol: "terminal", title: "Or let the agent fetch it", detail: "Connect Claude Code, Cursor, or Codex, then say what should change; the agent pulls the capture itself over MCP, image included.") {
                        Button("Agents…") { goToSettings(.agents) }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text("Open this again from Settings › General.")
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

    /// Closes the page and opens Settings on `tab`.
    private func goToSettings(_ tab: SettingsTab) {
        close()
        state.settingsTab = tab
        openSettings()
    }

    /// Symbol, title, one line beneath, and the key (or a control) on the trailing edge, the way
    /// Settings lays out a row.
    fileprivate struct Row<Trailing: View>: View {
        let symbol: String
        let title: String
        let detail: String
        @ViewBuilder let trailing: () -> Trailing

        init(symbol: String, title: String, detail: String, @ViewBuilder trailing: @escaping () -> Trailing) {
            self.symbol = symbol
            self.title = title
            self.detail = detail
            self.trailing = trailing
        }

        var body: some View {
            LabeledContent {
                trailing()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

extension HelpView.Row where Trailing == Text? {
    /// The common row: a key or a value in secondary text on the trailing edge, or nothing.
    init(symbol: String, title: String, detail: String, key: String?) {
        self.init(symbol: symbol, title: title, detail: detail) {
            key.map { Text($0).foregroundStyle(.secondary) }
        }
    }
}

/// The window that hosts `HelpView`: one instance, reopened in place.
@MainActor
final class HelpWindow {
    private var window: NSWindow?

    func show(state: AppState) {
        if window == nil {
            let created = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            // Not resizable: the page is one size, and a smaller display gets a scrolling Form instead.
            created.title = "Locant Help"
            created.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: HelpView(close: { [weak created] in created?.close() }).environment(state))
            created.contentView = hosting
            created.setContentSize(hosting.fittingSize)
            created.center()
            window = created
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}
