import AppKit
import ScreenCaptureKit

/// The cropped PNG plus what the sidecar needs to describe it.
struct CroppedImage: Sendable {
    var png: Data
    var widthPt: Double
    var heightPt: Double
    var scale: Double
    /// The rectangle actually captured, in global screen points.
    var crop: CGRect
}

enum ScreenCaptureFailure: Error {
    case noDisplay
    /// specs/capture-recovery.md R109: ScreenCaptureKit lists no displays while the Mac has some.
    case serviceStuck
    case cropOutsideImage
    case pngEncodingFailed
}

/// R4: crop at click time through ScreenCaptureKit. Every call goes through a filter that excludes
/// Locant's own windows, so Locant never appears in its own captures.
enum ScreenCapture {
    static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt once. Returns the current state; a fresh grant needs a relaunch to apply.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// R109: replayd, the process behind ScreenCaptureKit, can go stale (seen after a sleep and a
    /// monitor reconnect) and list windows but no displays, though the Mac has some.
    static func isServiceStuck(captureDisplays: Int, activeDisplays: Int) -> Bool {
        captureDisplays == 0 && activeDisplays > 0
    }

    /// CoreGraphics' count of active displays; needs no permission.
    static func activeDisplayCount() -> Int {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return 0 }
        return Int(count)
    }

    /// Every capture asks here first, so an empty display list always says why.
    private static func shareableContent() async throws -> SCShareableContent {
        #if DEBUG
        if await StuckSimulation.isActive { throw ScreenCaptureFailure.serviceStuck }
        #endif
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard content.displays.isEmpty else { return content }
        throw isServiceStuck(captureDisplays: 0, activeDisplays: activeDisplayCount())
            ? ScreenCaptureFailure.serviceStuck
            : ScreenCaptureFailure.noDisplay
    }

    /// R112: how many displays ScreenCaptureKit lists now; 0 when it lists none or fails.
    static func capturableDisplayCount() async -> Int {
        (try? await shareableContent().displays.count) ?? 0
    }

    /// The whole display containing `point`, own windows excluded, with its frame and scale.
    static func displayImage(containing point: CGPoint) async throws -> (image: CGImage, frame: CGRect, scale: CGFloat) {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.frame.contains(point) }) ?? content.displays.first else {
            throw ScreenCaptureFailure.noDisplay
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int((CGFloat(display.width) * scale).rounded())
        configuration.height = Int((CGFloat(display.height) * scale).rounded())
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return (image, display.frame, scale)
    }

    /// Captures `rect` (global screen points) from the display that contains its center.
    static func crop(_ rect: CGRect) async throws -> CroppedImage {
        let content = try await shareableContent()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first else {
            throw ScreenCaptureFailure.noDisplay
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let scale = CGFloat(filter.pointPixelScale)

        // Capture the whole display, then crop with the tested pixel math. A few extra milliseconds
        // buys a crop that cannot drift from the coordinates the sidecar records.
        let configuration = SCStreamConfiguration()
        configuration.width = Int((CGFloat(display.width) * scale).rounded())
        configuration.height = Int((CGFloat(display.height) * scale).rounded())
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.captureResolution = .best
        let full = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

        let visible = rect.intersection(display.frame).integral
        let pixels = Geometry.pixelRect(visible, inDisplay: display.frame, scale: scale)
            .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard !pixels.isEmpty, let cropped = full.cropping(to: pixels) else {
            throw ScreenCaptureFailure.cropOutsideImage
        }

        let rep = NSBitmapImageRep(cgImage: cropped)
        rep.size = NSSize(width: visible.width, height: visible.height) // marks the PNG as @scale
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw ScreenCaptureFailure.pngEncodingFailed
        }
        return CroppedImage(png: png, widthPt: visible.width, heightPt: visible.height, scale: Double(scale), crop: visible)
    }
}

#if DEBUG
/// specs/capture-recovery.md R114: `-simulateStuckCapture once|always` makes every capture throw
/// `.serviceStuck` without asking ScreenCaptureKit. `once` ends at the first restart (R112);
/// `always` lasts until quit. Debug builds only.
@MainActor
enum StuckSimulation {
    private static let mode = UserDefaults.standard.string(forKey: "simulateStuckCapture")
    private static var restarted = false

    static var isActive: Bool {
        switch mode {
        case "always": true
        case "once": !restarted
        default: false
        }
    }

    static func noteRestart() { restarted = true }
}
#endif
