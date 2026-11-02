import ApplicationServices
import XCTest
@testable import Locant

/// The reader's pure call on a failed accessibility message: only a failure that took the timeout
/// marks the app hung, so a quick refusal (an app that is gone, an attribute it does not have) is
/// not mistaken for one.
final class AccessibilityTimeoutTests: XCTestCase {
    func testOnlyAFailureThatTookTheTimeoutIsAHang() {
        let limit = Duration.seconds(AccessibilityReader.messagingTimeout)
        XCTAssertTrue(AccessibilityReader.timedOut(.cannotComplete, after: limit))
        XCTAssertTrue(AccessibilityReader.timedOut(.cannotComplete, after: .seconds(AccessibilityReader.messagingTimeout * 0.95)),
                      "a little under counts: the clock started before the call")
        XCTAssertFalse(AccessibilityReader.timedOut(.cannotComplete, after: .milliseconds(5)))
        XCTAssertFalse(AccessibilityReader.timedOut(.attributeUnsupported, after: limit * 2))
        XCTAssertFalse(AccessibilityReader.timedOut(.success, after: limit * 2))
    }

    func testTheTimeoutIsWellUnderTheSystemDefault() {
        XCTAssertLessThan(AccessibilityReader.messagingTimeout, 6, "the system default, which held the overlay for seconds per attribute")
        XCTAssertGreaterThanOrEqual(AccessibilityReader.messagingTimeout, 0.5, "Device Hub's hit test alone takes about 70 ms; Electron's first contact about half a second")
    }
}
