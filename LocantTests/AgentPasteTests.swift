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

    // 5: terminals by exact bundle id, each only after a calibration run; a terminal is not an agent.
    func testTerminalsByExactBundleId() {
        XCTAssertTrue(AgentPaste.isTerminal(bundleId: "com.apple.Terminal"))
        XCTAssertFalse(AgentPaste.isAgent(bundleId: "com.apple.Terminal"))
        XCTAssertFalse(AgentPaste.isTerminal(bundleId: "com.googlecode.iterm2"))
        XCTAssertFalse(AgentPaste.isTerminal(bundleId: "com.anysphere.sand"))
        XCTAssertFalse(AgentPaste.isTerminal(bundleId: nil))
    }

    // 6: R80, the text first, then the image; a terminal takes the text alone.
    func testTheTextGoesFirst() {
        XCTAssertEqual(AgentPaste.steps(terminal: false), [.text, .image])
        XCTAssertEqual(AgentPaste.steps(terminal: true), [.text])
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

    // 10: R83, the agent you used or picked last; a terminal only when picked.
    func testTheTargetFollowsYouAndHoldsAPick() {
        let terminal = AgentPaste.WindowRef(pid: 20, token: 1, appName: "Terminal", title: "zsh", isTerminal: true)
        let cursor = AgentPaste.WindowRef(pid: 30, token: 2, appName: "Cursor", title: "Agents", isTerminal: false)
        var target = AgentPaste.Target()
        target.agentCameForward(pid: 10, byLocant: false)
        XCTAssertEqual(target.lastAgentPID, 10)
        XCTAssertNil(target.pick)

        target.picked(terminal)
        target.agentCameForward(pid: 10, byLocant: true) // Locant's own activation during a paste
        XCTAssertEqual(target.pick, terminal)

        target.picked(cursor)
        target.agentCameForward(pid: 30, byLocant: false) // the picked app itself: the pick holds
        XCTAssertEqual(target.pick, cursor)
        XCTAssertEqual(target.lastAgentPID, 30)

        target.agentCameForward(pid: 10, byLocant: false) // another agent app, your doing
        XCTAssertNil(target.pick)
        XCTAssertEqual(target.lastAgentPID, 10)

        target.picked(terminal)
        target.pickVanished()
        XCTAssertNil(target.pick)
        XCTAssertEqual(target.lastAgentPID, 10)
    }

    // 11: R83, one section per app in the order the windows came; the target checked.
    func testTheMenuGroupsByAppAndChecksTheTarget() {
        let agents = AgentPaste.WindowRef(pid: 30, token: 1, appName: "Cursor", title: "Cursor Agents", isTerminal: false)
        let ide = AgentPaste.WindowRef(pid: 30, token: 2, appName: "Cursor", title: "inspire-ocean", isTerminal: false)
        let shell = AgentPaste.WindowRef(pid: 20, token: 3, appName: "Terminal", title: "zsh", isTerminal: true)
        let list = AgentPaste.WindowList(windows: [agents, shell, ide], focused: [2])

        var target = AgentPaste.Target()
        target.agentCameForward(pid: 30, byLocant: false)
        let byUse = AgentPaste.menu(list, target: target)
        XCTAssertEqual(byUse.map(\.appName), ["Cursor", "Terminal"])
        XCTAssertEqual(byUse[0].items.map(\.window.token), [1, 2])
        XCTAssertEqual(byUse.flatMap(\.items).filter(\.checked).map(\.window.token), [2])

        target.picked(shell)
        let byPick = AgentPaste.menu(list, target: target)
        XCTAssertEqual(byPick.flatMap(\.items).filter(\.checked).map(\.window.token), [3])

        XCTAssertEqual(AgentPaste.menu(AgentPaste.WindowList(), target: target), [])
    }

    // 12: R83, a long title is cut in the middle to 60 characters.
    func testMenuTitlesAreCutInTheMiddle() {
        XCTAssertEqual(AgentPaste.menuTitle("  zsh  "), "zsh")
        let long = String(repeating: "a", count: 40) + String(repeating: "b", count: 40)
        let cut = AgentPaste.menuTitle(long)
        XCTAssertEqual(cut.count, 60)
        XCTAssertTrue(cut.hasPrefix(String(repeating: "a", count: 29) + "…"))
        XCTAssertTrue(cut.hasSuffix(String(repeating: "b", count: 30)))
    }
}
