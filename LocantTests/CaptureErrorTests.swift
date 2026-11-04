import Foundation
import XCTest
@testable import Locant

/// specs/first-run.md R144: what a failure leaves in the log and in Diagnostics. Never an error's
/// description or user info, which can name a file or a window.
final class CaptureErrorTests: XCTestCase {
    func testPermissionsNoElementAndTheStuckServiceAreSaidInWords() {
        XCTAssertEqual(CaptureError.noAccessibilityPermission.reason, "no Accessibility permission")
        XCTAssertEqual(CaptureError.noScreenRecordingPermission.reason, "no Screen Recording permission")
        XCTAssertEqual(CaptureError.noElementUnderCursor.reason, "no element under the cursor")
        XCTAssertEqual(CaptureError.captureServiceStuck.reason, "screen capture stopped responding")
    }

    func testLocantsOwnFailureIsNamedByItsTypeAndCase() {
        XCTAssertEqual(CaptureError.captureFailed(ScreenCaptureFailure.noDisplay).reason, "ScreenCaptureFailure.noDisplay")
        XCTAssertEqual(CaptureError.capturing(ScreenCaptureFailure.cropOutsideImage).reason, "ScreenCaptureFailure.cropOutsideImage")
    }

    func testCancellationReadsCancelled() {
        XCTAssertEqual(CaptureError.captureFailed(CancellationError()).reason, "cancelled")
    }

    func testAnyOtherErrorIsItsDomainAndCodeThenTheUnderlyingOnes() {
        let write = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [
            NSFilePathErrorKey: "/Users/someone/Pictures/Locant/Point-Notes-20261103.png",
            NSLocalizedDescriptionKey: "You don't have permission to save the file “Point-Notes-20261103.png” in the folder “Locant”.",
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13),
        ])
        let reason = CaptureError.captureFailed(write).reason
        XCTAssertEqual(reason, "NSCocoaErrorDomain 513 (NSPOSIXErrorDomain 13)")
        XCTAssertFalse(reason.contains("someone"))
        XCTAssertFalse(reason.contains("Notes"))
        XCTAssertEqual(CaptureError.captureFailed(CocoaError(.fileWriteOutOfSpace)).reason, "NSCocoaErrorDomain 640")
    }
}
