import XCTest
@testable import Locant

final class AgentPasteTests: XCTestCase {
    // 1: exact bundle ids; a shared word is not enough. Grok Bot joined in v0.9.1 R83.
    func testTheAgentAppsByExactBundleId() {
        XCTAssertTrue(AgentPaste.isAgent(bundleId: "com.anthropic.claudefordesktop"))
        XCTAssertTrue(AgentPaste.isAgent(bundleId: "com.todesktop.230313mzl4w4u92"))
        XCTAssertTrue(AgentPaste.isAgent(bundleId: "com.openai.codex"))
        XCTAssertTrue(AgentPaste.isAgent(bundleId: "com.anysphere.sand"))
        for other in [
            "com.openai.chat", "com.steipete.codexbar", "com.anthropic.claude-code",
            "com.anthropic.claude-code-url-handler", "com.anthropic.claudefordesktop.helper",
            "com.openai.codex.helper", "com.apple.Terminal",
        ] {
            XCTAssertFalse(AgentPaste.isAgent(bundleId: other), other)
        }
        XCTAssertFalse(AgentPaste.isAgent(bundleId: nil))
    }

    // 2: the label names the app at once and the window when it is known.
    func testLabelNamesTheAppThenTheWindow() {
        XCTAssertEqual(AgentPaste.label(appName: nil, windowTitle: "x"), .init(lead: "→ no agent yet", title: nil))
        XCTAssertEqual(AgentPaste.label(appName: "Cursor", windowTitle: nil), .init(lead: "→ Cursor", title: nil))
        XCTAssertEqual(AgentPaste.label(appName: "Cursor", windowTitle: "   "), .init(lead: "→ Cursor", title: nil))
        XCTAssertEqual(AgentPaste.label(appName: "ChatGPT", windowTitle: " Deixis — v0.9 "), .init(lead: "→ ChatGPT", title: "Deixis — v0.9"))
    }

    // 3: the toast speaks only when nothing was pasted.
    func testToastExplainsOnlyAMissedPaste() {
        XCTAssertNil(AgentPaste.toastText(.pasted, appName: "Cursor"))
        XCTAssertNil(AgentPaste.toastText(.superseded, appName: "Cursor"))
        XCTAssertEqual(AgentPaste.toastText(.noAgent, appName: nil), "Copied · no agent yet")
        XCTAssertEqual(AgentPaste.toastText(.didNotComeForward, appName: "Cursor"), "Copied · Cursor didn't come forward")
        XCTAssertEqual(AgentPaste.toastText(.didNotComeForward, appName: nil), "Copied · the agent didn't come forward")
        XCTAssertEqual(AgentPaste.toastText(.noPermission, appName: "Cursor"), "Copied · pasting needs Accessibility")
        XCTAssertEqual(AgentPaste.toastText(.notTaken, appName: "Cursor"), "Copied · Cursor didn't take the paste")
        XCTAssertEqual(AgentPaste.toastText(.notTaken, appName: nil), "Copied · the agent didn't take the paste")
        XCTAssertEqual(AgentPaste.toastText(.noMessageBox, appName: "Cursor"), "Copied · no message box in Cursor")
    }

    // 4: Locant's own posted keys are known by their marker, and nothing else is.
    func testOwnEventsAreKnownByTheirMarker() {
        XCTAssertTrue(AgentPaste.isOwnEvent(userData: AgentPaste.eventMarker))
        XCTAssertFalse(AgentPaste.isOwnEvent(userData: 0))
        XCTAssertFalse(AgentPaste.isOwnEvent(userData: AgentPaste.eventMarker + 1))
    }

    // 5: R80, the text first, then the image.
    func testTheTextGoesFirst() {
        XCTAssertEqual(AgentPaste.steps, [.text, .image])
    }

    // 7: R82, a code editor is Monaco's input or sits within four levels of a monaco-editor.
    func testCodeEditorIsMonacos() {
        XCTAssertTrue(AgentPaste.isCodeEditor(classes: ["native-edit-context"], ancestorClasses: []))
        XCTAssertTrue(AgentPaste.isCodeEditor(classes: ["inputarea", "monaco-mouse-cursor-text"], ancestorClasses: []))
        XCTAssertTrue(AgentPaste.isCodeEditor(classes: [], ancestorClasses: [["overflow-guard"], ["monaco-editor", "no-user-select"]]))
        XCTAssertFalse(AgentPaste.isCodeEditor(classes: [], ancestorClasses: [["a"], ["b"], ["c"], ["d"], ["monaco-editor"]]))
        XCTAssertFalse(AgentPaste.isCodeEditor(
            classes: ["tiptap", "ProseMirror", "ui-prompt-input-editor__input"],
            ancestorClasses: [["ui-prompt-input-editor__content"], ["ui-prompt-input-editor"], ["monaco-workbench"]]
        ))
        XCTAssertFalse(AgentPaste.isCodeEditor(classes: ["inputarea"], ancestorClasses: []))
        XCTAssertFalse(AgentPaste.isCodeEditor(classes: [], ancestorClasses: []))
    }

    // 8: R82, focus already in a message box stays; otherwise the lowest box that is not code.
    func testMessageBoxIsTheFocusedOneOrTheLowest() {
        let box = AgentPaste.EditableArea(isFocused: false, isCodeEditor: false, bottom: 900)
        let lowerBox = AgentPaste.EditableArea(isFocused: false, isCodeEditor: false, bottom: 1040)
        let code = AgentPaste.EditableArea(isFocused: true, isCodeEditor: true, bottom: 1200)
        var focusedBox = box
        focusedBox.isFocused = true
        XCTAssertEqual(AgentPaste.messageBox(in: [lowerBox, focusedBox]), .focused)
        XCTAssertEqual(AgentPaste.messageBox(in: [code, box]), .focus(1))
        XCTAssertEqual(AgentPaste.messageBox(in: [box, code, lowerBox]), .focus(2))
        XCTAssertEqual(AgentPaste.messageBox(in: [code]), .onlyCodeEditor)
        XCTAssertEqual(AgentPaste.messageBox(in: []), .unknown)
    }

    // 9: R82, when focus could not be moved and code holds it, a ⌘V would land in code.
    func testNoPasteWhenCodeKeepsTheFocus() {
        let code = AgentPaste.EditableArea(isFocused: true, isCodeEditor: true, bottom: 1200)
        let box = AgentPaste.EditableArea(isFocused: false, isCodeEditor: false, bottom: 900)
        XCTAssertTrue(AgentPaste.canPaste(focusTook: true, areas: [code, box]))
        XCTAssertFalse(AgentPaste.canPaste(focusTook: false, areas: [code, box]))
        XCTAssertTrue(AgentPaste.canPaste(focusTook: false, areas: [box]))
    }

    // 10: R83, only a plain ⌘V in a listed app, with the capture still on the clipboard, while idle.
    func testOnlyAPasteOfTheCaptureInAListedAgentIsCompleted() {
        func completes(
            enabled: Bool = true, plainCommandV: Bool = true, isRepeat: Bool = false,
            frontmost: String? = "com.todesktop.230313mzl4w4u92", clipboard: Int = 7, capture: Int? = 7,
            idle: Bool = true, inFlight: Bool = false
        ) -> Bool {
            AgentPaste.completesPaste(
                enabled: enabled, plainCommandV: plainCommandV, isRepeat: isRepeat, frontmost: frontmost,
                clipboardCount: clipboard, captureCount: capture, idle: idle, inFlight: inFlight
            )
        }
        XCTAssertTrue(completes())
        XCTAssertTrue(completes(frontmost: "com.openai.codex"))
        XCTAssertTrue(completes(frontmost: "com.anysphere.sand"))
        XCTAssertFalse(completes(frontmost: "com.anthropic.claudefordesktop")) // keeps both halves itself
        XCTAssertFalse(completes(frontmost: "com.apple.Terminal"))
        XCTAssertFalse(completes(frontmost: nil))
        XCTAssertFalse(completes(enabled: false))
        XCTAssertFalse(completes(plainCommandV: false)) // ⌘⇧V, or another key
        XCTAssertFalse(completes(isRepeat: true))
        XCTAssertFalse(completes(clipboard: 8)) // something else was copied since
        XCTAssertFalse(completes(capture: nil)) // no capture yet
        XCTAssertFalse(completes(idle: false))
        XCTAssertFalse(completes(inFlight: true))
    }

    // 11: R83, the image follows only into a message box: not code, not a terminal pane, not a button.
    func testTheImageFollowsOnlyIntoAMessageBox() {
        XCTAssertTrue(AgentPaste.takesImagePaste(editable: true, classes: ["tiptap", "ProseMirror"], ancestorClasses: [["ui-prompt-input-editor"]]))
        XCTAssertFalse(AgentPaste.takesImagePaste(editable: false, classes: ["tiptap", "ProseMirror"], ancestorClasses: []))
        XCTAssertFalse(AgentPaste.takesImagePaste(editable: true, classes: ["xterm-helper-textarea"], ancestorClasses: []))
        XCTAssertFalse(AgentPaste.takesImagePaste(editable: true, classes: ["inputarea", "monaco-mouse-cursor-text"], ancestorClasses: []))
        XCTAssertFalse(AgentPaste.takesImagePaste(editable: true, classes: [], ancestorClasses: [["monaco-editor"]]))
    }
}
