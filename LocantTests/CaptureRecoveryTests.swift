import XCTest
@testable import Locant

/// specs/capture-recovery.md R109, R112: when the capture service counts as stuck, and what a
/// restart's re-check decides.
final class CaptureRecoveryTests: XCTestCase {
    // R109: stuck is no capture displays while CoreGraphics has at least one.
    func testStuckOnlyWhenCaptureListsNoDisplaysButTheMacHasSome() {
        XCTAssertTrue(ScreenCapture.isServiceStuck(captureDisplays: 0, activeDisplays: 1))
        XCTAssertTrue(ScreenCapture.isServiceStuck(captureDisplays: 0, activeDisplays: 3))
        XCTAssertFalse(ScreenCapture.isServiceStuck(captureDisplays: 0, activeDisplays: 0))
        XCTAssertFalse(ScreenCapture.isServiceStuck(captureDisplays: 1, activeDisplays: 1))
        XCTAssertFalse(ScreenCapture.isServiceStuck(captureDisplays: 3, activeDisplays: 3))
        XCTAssertFalse(ScreenCapture.isServiceStuck(captureDisplays: 1, activeDisplays: 0))
    }

    // R109: the stuck service keeps its own case; every other error is .captureFailed, as in R9.
    func testStuckServiceKeepsItsOwnCase() {
        guard case .captureServiceStuck = CaptureError.capturing(ScreenCaptureFailure.serviceStuck) else {
            return XCTFail("expected .captureServiceStuck")
        }
        guard case .captureFailed = CaptureError.capturing(ScreenCaptureFailure.noDisplay) else {
            return XCTFail("expected .captureFailed when the Mac has no display at all")
        }
        guard case .captureFailed = CaptureError.capturing(CocoaError(.fileWriteNoPermission)) else {
            return XCTFail("expected .captureFailed for a write error")
        }
    }

    func testStuckServiceMessage() {
        XCTAssertEqual(CaptureError.captureServiceStuck.message, "macOS screen capture stopped responding")
    }

    // R112: recovered once ScreenCaptureKit lists a display again.
    func testOutcomeAfterTheRecheck() {
        XCTAssertEqual(CaptureRecovery.outcome(displaysAfter: 1), .recovered)
        XCTAssertEqual(CaptureRecovery.outcome(displaysAfter: 3), .recovered)
        XCTAssertEqual(CaptureRecovery.outcome(displaysAfter: 0), .restartMac)
    }

    // R114: without the launch argument, nothing is simulated.
    @MainActor
    func testSimulationIsOffWithoutTheLaunchArgument() {
        XCTAssertFalse(StuckSimulation.isActive)
    }
}
