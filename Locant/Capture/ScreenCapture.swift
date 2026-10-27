import AppKit
import ScreenCaptureKit
import os

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
        let (image, scale) = try await fullImage(of: display, in: content)
        return (image, display.frame, scale)
    }

    /// Captures `rect` (global screen points) from the display that contains its center.
    static func crop(_ rect: CGRect) async throws -> CroppedImage {
        let content = try await shareableContent()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(center) }) ?? content.displays.first else {
            throw ScreenCaptureFailure.noDisplay
        }
        // Capture the whole display, then crop with the tested pixel math. A few extra milliseconds
        // buys a crop that cannot drift from the coordinates the sidecar records.
        let (full, scale) = try await fullImage(of: display, in: content)
        return try crop(rect, from: full, display: display.frame, scale: scale)
    }

    /// specs/frozen-screen.md R120: `rect` (global screen points) cut from `full`, the image of the
    /// display at `display` (global screen points) at `scale`. Pure; live and frozen crops share it.
    static func crop(_ rect: CGRect, from full: CGImage, display: CGRect, scale: CGFloat) throws -> CroppedImage {
        let visible = rect.intersection(display).integral
        let pixels = Geometry.pixelRect(visible, inDisplay: display, scale: scale)
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

    /// R119: every display, own windows excluded, at once. Each display is read in a task of its own
    /// that asks for the shareable content itself, since ScreenCaptureKit's objects cannot cross tasks.
    static func freeze() async throws -> FrozenScreen {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { throw ScreenCaptureFailure.noDisplay }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { throw ScreenCaptureFailure.noDisplay }
        let shots = try await withThrowingTaskGroup(of: FrozenScreen.Shot?.self) { group in
            for id in ids.prefix(Int(count)) {
                group.addTask {
                    let content = try await shareableContent()
                    guard let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
                    let (image, scale) = try await fullImage(of: display, in: content)
                    return FrozenScreen.Shot(display: display.frame, scale: scale, image: image)
                }
            }
            var shots: [FrozenScreen.Shot] = []
            for try await shot in group { if let shot { shots.append(shot) } }
            return shots
        }
        guard !shots.isEmpty else { throw ScreenCaptureFailure.noDisplay }
        return FrozenScreen(shots: shots)
    }

    /// R119: the freeze, or nil when it fails or has not answered within `limit`. The overlay waits
    /// on it before it takes key focus, and must not wait on a capture that never returns.
    static func freeze(within limit: Duration) async -> FrozenScreen? {
        let pending = OSAllocatedUnfairLock<CheckedContinuation<FrozenScreen?, Never>?>(initialState: nil)
        return await withCheckedContinuation { continuation in
            pending.withLock { $0 = continuation }
            let finish: @Sendable (FrozenScreen?) -> Void = { frozen in
                pending.withLock { waiting in
                    waiting?.resume(returning: frozen)
                    waiting = nil
                }
            }
            Task { finish(try? await freeze()) }
            Task {
                try? await Task.sleep(for: limit)
                finish(nil)
            }
        }
    }

    /// One display at full resolution, every window of Locant's left out, without the cursor.
    private static func fullImage(of display: SCDisplay, in content: SCShareableContent) async throws -> (image: CGImage, scale: CGFloat) {
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
        return (image, scale)
    }
}

/// specs/frozen-screen.md R119: every display as it was when an action began, Locant's own
/// windows left out. The overlay shows it under the dim, and crops are cut from it (R120).
struct FrozenScreen: Sendable {
    struct Shot: Sendable {
        /// The display's frame, global screen points.
        var display: CGRect
        var scale: CGFloat
        var image: CGImage
    }

    var shots: [Shot]

    /// The shot of the display that holds `point`.
    func shot(containing point: CGPoint) -> Shot? {
        shots.first { $0.display.contains(point) }
    }

    /// R120: `rect` cut from the display that holds its center; nil when no shot does, and the
    /// crop is then taken live.
    func crop(_ rect: CGRect) throws -> CroppedImage? {
        guard let shot = shot(containing: CGPoint(x: rect.midX, y: rect.midY)) else { return nil }
        return try ScreenCapture.crop(rect, from: shot.image, display: shot.display, scale: shot.scale)
    }
}

#if DEBUG
/// R114: `-simulateStuckCapture once|always` makes every capture throw
/// `.serviceStuck` without asking ScreenCaptureKit. `once` ends at the first restart (R112);
/// `always` lasts until quit. Debug builds only. Read from the launch arguments alone, so a
/// persisted default can never turn it on.
@MainActor
enum StuckSimulation {
    private static let mode = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["simulateStuckCapture"] as? String
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
