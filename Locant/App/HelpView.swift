import AppKit
import SwiftUI

/// v0.5 R43, R98: the one page that shows the whole product at once, a short line per row. Opens
/// once after the permission alerts, and any time from Settings › General. A standard
/// window in the Settings idiom (grouped rows, system type, no art): read it, close it, nothing to
/// click through.
struct HelpView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings
    var close: () -> Void = {}
    /// R98: the page's own height, measured; the Form scrolls on a display shorter than that.
    static let contentHeight: CGFloat = 871

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
