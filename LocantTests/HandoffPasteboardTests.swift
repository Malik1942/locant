import AppKit
import XCTest
@testable import Locant

/// specs/handoff.md R81, on a private named pasteboard: an in-process read calls the data provider just as
/// another app's read does, and the user's clipboard is never touched.
@MainActor
final class HandoffPasteboardTests: XCTestCase {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("LocantTests-\(UUID().uuidString)"))
    }

    private func makeHandoff(_ pasteboard: NSPasteboard) -> HandoffPasteboard {
        HandoffPasteboard(pasteboard: pasteboard, receiptLimit: .milliseconds(200), earlyReadWait: .milliseconds(50))
    }

    // 1: one type, offered lazily, marked transient.
    func testAnOfferIsOneTransientType() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let clipboard = makeHandoff(pasteboard)
        clipboard.offer(Data("note".utf8), as: .string)
        let types = Set(pasteboard.pasteboardItems?.first?.types ?? [])
        XCTAssertEqual(types, [.string, HandoffPasteboard.transientType])
        XCTAssertTrue(clipboard.holdsTemporary)
        XCTAssertTrue(clipboard.isOwn)
    }

    // 2: the receiver's read after arming is the receipt.
    func testAReadAfterArmingIsTheReceipt() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let clipboard = makeHandoff(pasteboard)
        clipboard.offer(Data("note".utf8), as: .string)
        clipboard.arm()
        XCTAssertEqual(pasteboard.string(forType: .string), "note")
        let read = await clipboard.receipt()
        XCTAssertTrue(read)
    }

    // 3: no read, no receipt, once the limit has passed.
    func testNoReadIsNoReceipt() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let clipboard = makeHandoff(pasteboard)
        clipboard.offer(Data("note".utf8), as: .string)
        clipboard.arm()
        let read = await clipboard.receipt()
        XCTAssertFalse(read)
    }

    // 4: a read before arming cannot come again (the data is cached), so the wait stands in for it.
    func testAnEarlyReadIsWaitedOut() async {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let clipboard = makeHandoff(pasteboard)
        clipboard.offer(Data("note".utf8), as: .string)
        _ = pasteboard.string(forType: .string)
        clipboard.arm()
        let start = ContinuousClock.now
        let read = await clipboard.receipt()
        XCTAssertTrue(read)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - start, .milliseconds(50))
    }

    // 5: someone else's write ends Locant's ownership, and restore leaves their copy alone.
    func testAForeignWriteIsNeitherOwnedNorRestored() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let clipboard = makeHandoff(pasteboard)
        clipboard.offer(Data("note".utf8), as: .string)
        pasteboard.clearContents()
        pasteboard.setString("mine", forType: .string)
        XCTAssertFalse(clipboard.isOwn)
        clipboard.restore(markdown: "## Locant capture", png: Data([0x89, 0x50]))
        XCTAssertEqual(pasteboard.string(forType: .string), "mine")
    }

    // 6: restore puts Return's item back: both types, not transient, Locant's again.
    func testRestorePutsReturnsItemBack() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let clipboard = makeHandoff(pasteboard)
        clipboard.offer(Data([1, 2, 3]), as: .png)
        clipboard.restore(markdown: "## Locant capture", png: Data([0x89, 0x50]))
        XCTAssertEqual(Set(pasteboard.pasteboardItems?.first?.types ?? []), [.png, .string])
        XCTAssertEqual(pasteboard.string(forType: .string), "## Locant capture")
        XCTAssertFalse(clipboard.holdsTemporary)
        XCTAssertTrue(clipboard.isOwn)
    }

    // 7: with no temporary item written, restore writes nothing.
    func testRestoreWithoutAnOfferWritesNothing() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("return's", forType: .string)
        let clipboard = makeHandoff(pasteboard)
        let count = pasteboard.changeCount
        clipboard.restore(markdown: "## Locant capture", png: Data([0x89, 0x50]))
        XCTAssertEqual(pasteboard.changeCount, count)
    }
}
