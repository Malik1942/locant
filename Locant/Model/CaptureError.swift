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

    /// specs/first-run.md R144: why, for the log and Diagnostics. Never an error's description or user
    /// info, which can name a file or a window.
    var reason: String {
        switch self {
        case .noAccessibilityPermission: "no Accessibility permission"
        case .noScreenRecordingPermission: "no Screen Recording permission"
        case .noElementUnderCursor: "no element under the cursor"
        case .captureFailed(let error): Self.reason(of: error)
        case .captureServiceStuck: "screen capture stopped responding"
        }
    }

    /// An error of Locant's own by its type and case, cancellation as such, and any other error by its
    /// domain and code, then its underlying error's: "NSCocoaErrorDomain 513 (NSPOSIXErrorDomain 13)".
    private static func reason(of error: any Error) -> String {
        if error is CancellationError { return "cancelled" }
        let mirror = Mirror(reflecting: error)
        if mirror.displayStyle == .enum, mirror.children.isEmpty { return "\(type(of: error)).\(error)" }
        let error = error as NSError
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return "\(error.domain) \(error.code)" }
        return "\(error.domain) \(error.code) (\(underlying.domain) \(underlying.code))"
    }
}
