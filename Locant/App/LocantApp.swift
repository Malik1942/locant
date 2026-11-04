import AppKit
import SwiftUI

/// The entry point. v0.7.1 R53: `Locant --mcp` is the MCP server on stdio and never touches
/// AppKit; anything else is the app.
@main
enum Main {
    @MainActor static func main() {
        if let options = MCPServer.Options(arguments: CommandLine.arguments) {
            MCPServer.serve(options)
            return
        }
        LocantApp.main()
    }
}

/// LSUIElement app: no Dock icon, no document windows. Two scenes: the menu bar item (R10, a
/// standard menu rendered by `MenuBarExtra`) and Settings (v0.3 R19). The delegate keeps the
/// permission alerts and `AppState`.
struct LocantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenu()
                .environment(delegate.state)
        } label: {
            Image(systemName: "hand.point.up.left")
                .accessibilityLabel("Locant")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(delegate.state)
        }
        .windowResizability(.contentSize)
        .commands {
            // ⌘H in a UIElement app would hide every window, ball included, with no Dock icon to
            // bring them back. In Settings it puts the window away instead; Settings… reopens it.
            CommandGroup(replacing: .appVisibility) {
                Button("Hide Settings") { NSApp.keyWindow?.orderOut(nil) }
                    .keyboardShortcut("h")
            }
            // The generated Window menu's Minimize did nothing for the Settings window; these act
            // on the key window directly. The menu is invisible in a UIElement app; only the keys matter.
            CommandGroup(replacing: .windowSize) {
                Button("Minimize") { NSApp.keyWindow?.miniaturize(nil) }
                    .keyboardShortcut("m")
                Button("Zoom") { NSApp.keyWindow?.zoom(nil) }
            }
        }
    }
}

/// R10: Point (was Capture), Open capture folder, Settings…, Quit; v0.4 Show before & after (R44).
/// Iterations are collected by themselves since v0.6 R52, so "See what changed" left the menu.
/// R97: the help page is not here; it is rarely opened, and Settings › General has it.
private struct StatusMenu: View {
    @Environment(AppState.self) private var state
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Hotkeys show as the menu's own key equivalents, grey and right-aligned like ⌘, and ⌘Q.
        // A double-tap has no key equivalent, so it stays in Point's title (specs/first-run.md R142).
        let point = pointItem
        Button(point.title) {
            state.beginCapture()
        }
        .keyboardShortcut(point.keyEquivalent?.keyboardShortcut)
        Button("Show before & after") { state.showBeforeAfter() }
        Divider()
        Button("Snap") { state.beginAction(.snap) }
            .keyboardShortcut(shortcut("snap"))
        Button("Text") { state.beginAction(.text) }
            .keyboardShortcut(shortcut("text"))
        Button("Color") { state.beginColorPick() }
            .keyboardShortcut(shortcut("color"))
        Button("Cut") { state.beginAction(.cut) }
            .keyboardShortcut(shortcut("cut"))
        Divider()
        Button("Open capture folder") {
            state.openCaptureFolder()
        }
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Locant") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// R142: every key that starts Point, "Point (⌃⌃)" beside ⌃⌥1 by default.
    private var pointItem: (title: String, keyEquivalent: Hotkey?) {
        Hotkey.pointMenuItem(Hotkey.pointKeys(capture: state.preferences.hotkey, action: state.preferences.actionHotkeys["point"]))
    }

    private func shortcut(_ action: String) -> KeyboardShortcut? {
        state.preferences.actionHotkeys[action]?.keyboardShortcut
    }
}

private extension Hotkey {
    /// The chord as a menu key equivalent (`Hotkey.keyEquivalent`). A double-tap, or a key without a
    /// single character (an arrow, a function key), has none.
    var keyboardShortcut: KeyboardShortcut? {
        guard let equivalent = keyEquivalent else { return nil }
        let modifiers = equivalent.modifiers
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(equivalent.character), modifiers: eventModifiers)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // v0.9 R67: as the test host, on a CI runner, the app has no grants and nobody to click
        // Continue; the tests are over pure functions and never need them.
        if !Self.isTestHost {
            requestPermissionsIfNeeded()
        }
        state.start()
    }

    private static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }

    // MARK: Permissions

    /// PRD permissions spec: one plain sentence before each system prompt.
    private func requestPermissionsIfNeeded() {
        if !AccessibilityReader.isTrusted(prompt: false) {
            explain("Locant reads what is under your cursor through Accessibility. Nothing leaves the machine.")
            _ = AccessibilityReader.isTrusted(prompt: true)
        }
        if !ScreenCapture.hasPermission() {
            explain("Locant captures the element through Screen Recording. Nothing leaves the machine. macOS applies this grant after Locant reopens, and offers Quit & Reopen when you turn it on.")
            ScreenCapture.requestPermission()
        }
    }

    private func explain(_ sentence: String) {
        let alert = NSAlert()
        alert.messageText = "Locant"
        alert.informativeText = sentence
        alert.addButton(withTitle: "Continue")
        NSApp.activate()
        alert.runModal()
    }
}
