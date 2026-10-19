import AppKit
import XCTest
@testable import Locant

/// The monitor's pure event handling (no tap, no monitors are started) and the conflict check.
@MainActor
final class HotkeyTests: XCTestCase {
    private func monitor(_ bindings: [HotkeyMonitor.Binding]) -> HotkeyMonitor {
        HotkeyMonitor(bindings: bindings)
    }

    // MARK: Double-tap

    func testDoubleTapFiresInsideTheWindow() {
        var fired = 0
        let m = monitor([.init(.doubleTap(.control)) { fired += 1 }])
        m.handleFlags([.control], keyCode: 59, timestamp: 1.00)
        m.handleFlags([], keyCode: 59, timestamp: 1.05)
        m.handleFlags([.control], keyCode: 59, timestamp: 1.20)
        XCTAssertEqual(fired, 1)
        m.handleFlags([], keyCode: 59, timestamp: 1.25)
        m.handleFlags([.control], keyCode: 59, timestamp: 1.30)
        XCTAssertEqual(fired, 1, "the third press starts a new pair")
    }

    func testDoubleTapTooSlowOrWrongModifierDoesNotFire() {
        var fired = 0
        let m = monitor([.init(.doubleTap(.control)) { fired += 1 }])
        m.handleFlags([.control], keyCode: 59, timestamp: 1.0)
        m.handleFlags([], keyCode: 59, timestamp: 1.1)
        m.handleFlags([.control], keyCode: 59, timestamp: 1.0 + HotkeyMonitor.window + 0.01)
        XCTAssertEqual(fired, 0)
        m.handleFlags([], keyCode: 59, timestamp: 2.0)
        m.handleFlags([.option], keyCode: 58, timestamp: 2.1)
        m.handleFlags([], keyCode: 58, timestamp: 2.2)
        m.handleFlags([.option], keyCode: 58, timestamp: 2.3)
        XCTAssertEqual(fired, 0, "double-tap Option is not bound")
    }

    func testDoubleTapWithAnotherModifierHeldIsAChord() {
        var fired = 0
        let m = monitor([.init(.doubleTap(.control)) { fired += 1 }])
        m.handleFlags([.command], keyCode: 55, timestamp: 1.0)
        m.handleFlags([.command, .control], keyCode: 59, timestamp: 1.1)
        m.handleFlags([.command], keyCode: 59, timestamp: 1.2)
        m.handleFlags([.command, .control], keyCode: 59, timestamp: 1.3)
        XCTAssertEqual(fired, 0)
    }

    func testRightCommandTellsTheKeysApart() {
        var any = 0, right = 0
        let m = monitor([.init(.doubleTap(.command)) { any += 1 }, .init(.doubleTap(.rightCommand)) { right += 1 }])
        m.handleFlags([.command], keyCode: 55, timestamp: 1.0)
        m.handleFlags([], keyCode: 55, timestamp: 1.1)
        m.handleFlags([.command], keyCode: 55, timestamp: 1.2)
        XCTAssertEqual(any, 1)
        XCTAssertEqual(right, 0, "left Command is not the right key")
        m.handleFlags([], keyCode: 54, timestamp: 2.0)
        m.handleFlags([.command], keyCode: 54, timestamp: 2.1)
        m.handleFlags([], keyCode: 54, timestamp: 2.2)
        m.handleFlags([.command], keyCode: 54, timestamp: 2.3)
        XCTAssertEqual(any, 2)
        XCTAssertEqual(right, 1)
    }

    // MARK: Chord

    func testChordFiresOnlyItsBindingAndIsSwallowed() {
        var snap = 0, text = 0
        let m = monitor([
            .init(Preferences.defaultActionHotkey("snap")!) { snap += 1 },
            .init(Preferences.defaultActionHotkey("text")!) { text += 1 },
        ])
        XCTAssertTrue(m.handleKey([.control, .option], keyCode: 19))
        XCTAssertEqual(snap, 1)
        XCTAssertEqual(text, 0)
        XCTAssertFalse(m.handleKey([.control, .option, .shift], keyCode: 19), "extra modifier is a different chord")
        XCTAssertFalse(m.handleKey([.option], keyCode: 19), "⌥2 alone types ™ and is left alone")
        XCTAssertFalse(m.handleKey([.control, .option], keyCode: 18), "⌃⌥1 is not bound here")
        XCTAssertEqual(snap, 1)
    }

    func testHeldChordFiresOnceButStaysSwallowed() {
        var fired = 0
        let m = monitor([.init(Preferences.defaultActionHotkey("cut")!) { fired += 1 }])
        XCTAssertTrue(m.handleKey([.control, .option], keyCode: 23))
        XCTAssertTrue(m.handleKey([.control, .option], keyCode: 23, isRepeat: true))
        XCTAssertTrue(m.handleKey([.control, .option], keyCode: 23, isRepeat: true))
        XCTAssertEqual(fired, 1)
    }

    func testTapEventRoutesByKind() {
        var fired = 0
        let m = monitor([.init(Preferences.defaultActionHotkey("point")!) { fired += 1 }])
        let down = KeyEventTap.KeyEvent(kind: .keyDown, keyCode: 18, flags: [.control, .option], isRepeat: false, timestamp: 1)
        XCTAssertTrue(m.handle(down))
        let flags = KeyEventTap.KeyEvent(kind: .flagsChanged, keyCode: 59, flags: [.control], isRepeat: false, timestamp: 1)
        XCTAssertFalse(m.handle(flags), "a modifier press is never swallowed")
        XCTAssertEqual(fired, 1)
    }

    func testCapsLockAndFnAreIgnoredInChords() {
        XCTAssertEqual(KeyModifiers([.control, .option, .capsLock, .function]), [.control, .option])
    }

    // MARK: Conflicts

    func testCarbonModifiersConvert() {
        XCTAssertEqual(KeyModifiers(carbon: 256), [.command])
        XCTAssertEqual(KeyModifiers(carbon: 768), [.command, .shift])
        XCTAssertEqual(KeyModifiers(carbon: 6144), [.control, .option])
        XCTAssertEqual(KeyModifiers(carbon: 4864), [.control, .shift, .command])
        XCTAssertEqual(KeyModifiers(carbon: 0), [])
    }

    func testSystemShortcutMatchIsExact() {
        let screenshot = SystemShortcut(keyCode: 21, modifiers: [.command, .shift]) // ⇧⌘4
        let list = [screenshot, SystemShortcut(keyCode: 49, modifiers: [.command])]
        XCTAssertTrue(HotkeyConflicts.matchesSystem(keyCode: 21, modifiers: [.command, .shift], in: list))
        XCTAssertFalse(HotkeyConflicts.matchesSystem(keyCode: 21, modifiers: [.control, .option], in: list), "⌃⌥4 is not ⇧⌘4")
        XCTAssertFalse(HotkeyConflicts.matchesSystem(keyCode: 21, modifiers: [.command, .shift, .control], in: list))
    }

    func testDefaultsAreNotSystemShortcutsOnThisMac() {
        let system = HotkeyConflicts.systemShortcuts()
        XCTAssertFalse(system.isEmpty, "macOS reports its shortcut list")
        for action in Preferences.hotkeyActions {
            guard case .chord(let code, let modifiers, _) = Preferences.defaultActionHotkey(action)! else { return XCTFail() }
            XCTAssertFalse(HotkeyConflicts.matchesSystem(keyCode: code, modifiers: modifiers, in: system), "\(action) default clashes with macOS")
        }
    }

    func testCheckReportsLocantClashFirst() {
        let p = Preferences(defaults: isolatedDefaults())
        let snap = Preferences.defaultActionHotkey("snap")!
        XCTAssertEqual(HotkeyConflicts.check(snap, for: "text", in: p).first, .locant(action: "snap"))
        XCTAssertEqual(HotkeyConflicts.check(snap, for: "snap", in: p), [])
        XCTAssertEqual(HotkeyConflicts.check(.doubleTap(.control), for: "point", in: p).first, .locant(action: "capture"))
        XCTAssertEqual(HotkeyConflict.locant(action: "snap").message, "Already used for Snap.")
        XCTAssertEqual(HotkeyConflict.locant(action: "capture").message, "Already used for Point.")
        XCTAssertEqual(HotkeyConflict.system.message, "Also a macOS shortcut; Locant takes it first.")
    }
}
