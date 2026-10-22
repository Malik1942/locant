import Foundation

enum CaptureError: Error, Sendable {
    case noAccessibilityPermission
    case noScreenRecordingPermission
    case noElementUnderCursor
    case captureFailed(any Error)
    /// specs/capture-recovery.md R109: ScreenCaptureKit lists no displays while the Mac has some.
    case captureServiceStuck

    /// Short text for the 1-second toast.
    var message: String {
        switch self {
        case .noAccessibilityPermission: "Locant needs Accessibility access"
        case .noScreenRecordingPermission: "Locant needs Screen Recording access"
        case .noElementUnderCursor: "No accessibility element under the cursor"
        case .captureFailed: "Capture failed"
        case .captureServiceStuck: "macOS screen capture stopped responding"
        }
    }

    /// R109: what a capture threw, as the user hears it. Only the stuck service has its own case.
    static func capturing(_ error: any Error) -> CaptureError {
        if let failure = error as? ScreenCaptureFailure, failure == .serviceStuck { return .captureServiceStuck }
        return .captureFailed(error)
    }
}
