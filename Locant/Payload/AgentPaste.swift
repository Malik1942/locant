import AppKit
import Carbon.HIToolbox

/// v0.8.1 R63, specs/handoff.md R80–R83: after Return, the capture is handed to the agent: the text, then the
/// image. The decisions are pure and tested here; `AgentPaster` performs them.
enum AgentPaste {
    /// Agent apps by exact bundle id, verified on this Mac on Sep 17, 2026 (Grok Bot and Antigravity on
    /// Oct 1, each after a run showing its message box takes the text and then the image). Never
    /// matched by name: ChatGPT Classic (`com.openai.chat`), CodexBar, and the Claude app's
    /// background-only Claude Code copies share words with these and are not agents.
    static let bundleIds: Set<String> = [
        "com.anthropic.claudefordesktop", // Claude
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.openai.codex", // Codex, installed as ChatGPT.app
        "com.anysphere.sand", // Grok Bot, specs/handoff.md R83
        "com.google.antigravity", // Antigravity, specs/handoff.md R83
    ]

    static func isAgent(bundleId: String?) -> Bool {
        bundleId.map { bundleIds.contains($0) } ?? false
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

    /// How a hand-off ended. `.superseded`: a newer capture started, or the clipboard changed, before
    /// anything was pasted; the user has moved on, so nothing is said.
    enum Outcome: Equatable, Sendable {
        case pasted, noAgent, noPermission, didNotComeForward, superseded
        /// specs/handoff.md R81: the agent never read the text.
        case notTaken
        /// specs/handoff.md R82: the window's only editable text is a code editor.
        case noMessageBox
    }

    /// What the toast says when nothing was pasted; nil when the paste itself is the feedback.
    static func toastText(_ outcome: Outcome, appName: String?) -> String? {
        let app = appName ?? "the agent"
        return switch outcome {
        case .pasted, .superseded: nil
        case .noAgent: "Copied · no agent yet"
        case .noPermission: "Copied · pasting needs Accessibility"
        case .didNotComeForward: "Copied · \(app) didn't come forward"
        case .notTaken: "Copied · \(app) didn't take the paste"
        case .noMessageBox: "Copied · no message box in \(app)"
        }
    }

    /// Marks the keys Locant posts, in `eventSourceUserData`, so its own tap lets them through.
    /// "LOCANT" in ASCII; nothing else sets it.
    static let eventMarker: Int64 = 0x4C_4F_43_41_4E_54

    static func isOwnEvent(userData: Int64) -> Bool {
        userData == eventMarker
    }

    // MARK: The hand-off (specs/handoff.md R80–R83)

    /// R80: one paste of the hand-off.
    enum Step: Equatable, Sendable {
        case text, image
    }

    /// R80: the text first, then the image. Measured Oct 1, 2026: Cursor and Grok Bot keep only the
    /// image of an item carrying both, Codex only the text.
    static let steps: [Step] = [.text, .image]

    /// R82: Monaco's input (`native-edit-context` since VS Code's EditContext, which Cursor 3.22 uses;
    /// the `inputarea` textarea before it), or anything within four levels of a `monaco-editor`. The
    /// window-wide `monaco-workbench` does not count: Cursor's and VS Code's chat boxes sit in it too.
    static func isCodeEditor(classes: [String], ancestorClasses: [[String]]) -> Bool {
        if classes.contains("native-edit-context") { return true }
        if classes.contains("inputarea"), classes.contains("monaco-mouse-cursor-text") { return true }
        return ancestorClasses.prefix(4).contains { $0.contains("monaco-editor") }
    }

    /// R82: one editable text area in the target window, as the reader saw it.
    struct EditableArea: Equatable, Sendable {
        var isFocused: Bool
        var isCodeEditor: Bool
        /// The bottom edge in screen points, top-left origin: larger is lower on screen.
        var bottom: Double
    }

    /// R82: where the paste goes in the target window.
    enum MessageBox: Equatable, Sendable {
        /// Focus is already in a message box.
        case focused
        /// Put focus in the area at this index first.
        case focus(Int)
        /// Only a code editor takes text here: no paste.
        case onlyCodeEditor
        /// Nothing editable was read (no tree yet): paste where the app's own focus is.
        case unknown
    }

    static func messageBox(in areas: [EditableArea]) -> MessageBox {
        if areas.contains(where: { $0.isFocused && !$0.isCodeEditor }) { return .focused }
        let boxes = areas.indices.filter { !areas[$0].isCodeEditor }
        if let lowest = boxes.max(by: { areas[$0].bottom < areas[$1].bottom }) { return .focus(lowest) }
        return areas.isEmpty ? .unknown : .onlyCodeEditor
    }

    /// R82: after Locant set focus on a message box. When it did not take and a code editor still holds
    /// the focus, a ⌘V would land in code: no paste.
    static func canPaste(focusTook: Bool, areas: [EditableArea]) -> Bool {
        focusTook || !areas.contains { $0.isFocused && $0.isCodeEditor }
    }

    /// R83: the apps whose message box drops a half of Return's item, each after a calibration run:
    /// Cursor, Codex, and Grok Bot on Oct 1, 2026. Claude and Antigravity keep both halves and are not
    /// listed.
    static let completingBundleIds: Set<String> = [
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.openai.codex", // Codex, installed as ChatGPT.app
        "com.anysphere.sand", // Grok Bot
    ]

    /// R83: whether a key-down is the paste Locant completes: a plain ⌘V, not a repeat, in a listed
    /// app, while the clipboard still holds the newest capture's item and Locant is doing nothing else.
    static func completesPaste(
        enabled: Bool, plainCommandV: Bool, isRepeat: Bool, frontmost: String?,
        clipboardCount: Int, captureCount: Int?, idle: Bool, inFlight: Bool
    ) -> Bool {
        guard enabled, plainCommandV, !isRepeat, idle, !inFlight else { return false }
        guard let frontmost, completingBundleIds.contains(frontmost) else { return false }
        return captureCount == clipboardCount
    }

    /// R83: whether the focused element takes an image paste: editable text that is neither a code
    /// editor nor a terminal pane (xterm's input, as in Cursor's and VS Code's terminal).
    static func takesImagePaste(editable: Bool, classes: [String], ancestorClasses: [[String]]) -> Bool {
        editable && !classes.contains("xterm-helper-textarea")
            && !isCodeEditor(classes: classes, ancestorClasses: ancestorClasses)
    }
}

/// specs/handoff.md R80: what one hand-off delivers, and where.
struct Handoff {
    let app: NSRunningApplication
    let markdown: String
    let png: Data
}

/// v0.8.1 R63, specs/handoff.md R80–R82: brings the agent forward, puts focus in its message box, and pastes the
/// text, then the image; never Return. Not pure; not unit tested. Every step checks the agent is still
/// in front, so ⌘V never lands in the app the user pointed at.
@MainActor
enum AgentPaster {
    /// After the agent is frontmost, before ⌘V: Electron puts focus back in its composer.
    static let settle: Duration = .milliseconds(150)
    /// specs/handoff.md R81: a Space switch took up to about a second on Oct 1, 2026.
    static let comeForwardLimit: Duration = .milliseconds(1500)
    /// specs/handoff.md R81: between the text's receipt and the image's item.
    static let stepGap: Duration = .milliseconds(120)

    /// `newerCapture` and the clipboard's ownership are asked before every step; `clipboard` was made
    /// right after Return's write. Whenever the hand-off ends with a temporary item of its own on the
    /// clipboard, Return's item goes back.
    static func paste(
        _ handoff: Handoff?, clipboard: HandoffPasteboard, reader: AccessibilityReader,
        newerCapture: @escaping @MainActor @Sendable () -> Bool
    ) async -> AgentPaste.Outcome {
        guard let handoff, !handoff.app.isTerminated else { return .noAgent }
        guard CGPreflightPostEventAccess() else { return .noPermission }
        defer { clipboard.restore(markdown: handoff.markdown, png: handoff.png) }
        let proceed: @MainActor @Sendable () -> Bool = { !newerCapture() && clipboard.isOwn }
        await waitForKeysUp()
        guard proceed() else { return .superseded }
        guard await bringForward(handoff, reader: reader, proceed: proceed) else {
            return proceed() ? .didNotComeForward : .superseded
        }
        try? await Task.sleep(for: settle)
        guard proceed() else { return .superseded }
        guard await reader.focusMessageBox(pid: handoff.app.processIdentifier) else { return .noMessageBox }
        var pasted = false
        for step in AgentPaste.steps {
            if pasted { try? await Task.sleep(for: stepGap) }
            await waitForKeysUp()
            guard proceed() else { return pasted ? .pasted : .superseded }
            guard await isInFront(handoff, reader: reader) else { return pasted ? .pasted : .didNotComeForward }
            switch step {
            case .text: clipboard.offer(Data(handoff.markdown.utf8), as: .string)
            case .image: clipboard.offer(handoff.png, as: .png)
            }
            clipboard.arm()
            post(keyCode: pasteKeyCode(), flags: .maskCommand)
            let read = await clipboard.receipt()
            if step == .text, !read { return .notTaken }
            pasted = true
        }
        return .pasted
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

    /// Activates, then polls every
    /// 25 ms up to `comeForwardLimit`: a notification never comes when the app is already in front.
    /// After 300 ms, accessibility raises it again; `proceed` is checked at the top of every tick,
    /// before that raise, so it never pulls the agent in front of a capture the user just started.
    private static func bringForward(
        _ handoff: Handoff, reader: AccessibilityReader, proceed: @MainActor @Sendable () -> Bool
    ) async -> Bool {
        let app = handoff.app
        if await isInFront(handoff, reader: reader) { return true }
        _ = app.activate(options: [])
        let ticks = Int(comeForwardLimit / .milliseconds(25))
        for tick in 1...ticks {
            try? await Task.sleep(for: .milliseconds(25))
            guard proceed() else { return false }
            if await isInFront(handoff, reader: reader) { return true }
            if app.isTerminated { return false }
            if tick == 12 { await reader.raise(pid: app.processIdentifier) }
        }
        return false
    }

    /// R81: frontmost, with a window on screen (a Space switch has finished).
    private static func isInFront(_ handoff: Handoff, reader: AccessibilityReader) async -> Bool {
        isFrontmost(handoff.app) && hasWindowOnScreen(pid: handoff.app.processIdentifier)
    }

    /// R83: the user's own ⌘V is pasting the text item `clipboard` offered at the key. On its receipt,
    /// if the caret is in a message box, the image follows with one ⌘V of Locant's; then Return's item
    /// goes back. The user's ⌘ may still be down: the posted key carries ⌘ itself, so that is no leak.
    static func addImage(
        after clipboard: HandoffPasteboard, in app: NSRunningApplication, markdown: String, png: Data,
        reader: AccessibilityReader, newerCapture: @escaping @MainActor @Sendable () -> Bool
    ) async {
        defer { clipboard.restore(markdown: markdown, png: png) }
        guard await clipboard.receipt() else { return }
        try? await Task.sleep(for: stepGap)
        guard !newerCapture(), clipboard.isOwn, isFrontmost(app), CGPreflightPostEventAccess() else { return }
        guard await reader.focusTakesImagePaste(pid: app.processIdentifier) else { return }
        guard clipboard.isOwn, isFrontmost(app) else { return }
        clipboard.offer(png, as: .png)
        clipboard.arm()
        post(keyCode: pasteKeyCode(), flags: .maskCommand)
        _ = await clipboard.receipt()
    }

    private static func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    /// A normal-layer window of the app, taller than a title strip, among the windows on screen now.
    private static func hasWindowOnScreen(pid: pid_t) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid, info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any], let height = bounds["Height"] as? Double else { return false }
            return height > 100
        }
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
    static func pasteKeyCode() -> CGKeyCode {
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
