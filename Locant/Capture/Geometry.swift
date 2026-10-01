import CoreGraphics
import Foundation

/// Pure coordinate functions. Three spaces meet here:
/// - AppKit: bottom-left origin at the primary display, points. `NSEvent.mouseLocation`, `NSScreen.frame`.
/// - CG / AX: top-left origin at the primary display, points. Accessibility frames, `CGWindowList`
///   bounds, `SCDisplay.frame` all share this space.
/// - Display-local pixels: origin at one display's top-left, scaled by its backing factor.
enum Geometry {
    static let cropPadding: Double = 40
    static let fallbackCropSide: Double = 120

    // MARK: AppKit ↔ CG

    static func cgPoint(fromAppKit p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    static func appKitPoint(fromCG p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    static func cgRect(fromAppKit r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func appKitRect(fromCG r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    // MARK: Crop (R4)

    /// Element frame plus padding, clamped to the target window and then to the display.
    /// Without an element: a square around the click point plus the same padding.
    static func cropRect(
        element: CGRect?,
        clickPoint: CGPoint,
        window: CGRect?,
        display: CGRect,
        padding: Double = cropPadding
    ) -> CGRect {
        let base = element ?? CGRect(
            x: clickPoint.x - fallbackCropSide / 2,
            y: clickPoint.y - fallbackCropSide / 2,
            width: fallbackCropSide,
            height: fallbackCropSide
        )
        var rect = base.insetBy(dx: -padding, dy: -padding)
        if let window {
            let clamped = rect.intersection(window)
            if !clamped.isEmpty { rect = clamped }
        }
        let onDisplay = rect.intersection(display)
        return onDisplay.isEmpty ? display : onDisplay.integral
    }

    /// A set covers at most this share of its display before each element gets its own crop.
    static let setCropFraction: Double = 0.6

    /// v0.8 R58: the crops for several selected elements. One crop of their union plus padding when
    /// every frame's center is on `display` and the union covers less than `setCropFraction` of it;
    /// otherwise one crop per element, each on the display that holds its center (`displayFor`).
    static func cropRects(
        for frames: [CGRect],
        display: CGRect,
        displayFor: (CGPoint) -> CGRect,
        padding: Double = cropPadding
    ) -> [CGRect] {
        guard let first = frames.first else { return [] }
        let centers = frames.map { CGPoint(x: $0.midX, y: $0.midY) }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        let together = centers.allSatisfy { display.contains($0) }
            && union.width * union.height < setCropFraction * display.width * display.height
        if together {
            return [cropRect(element: union, clickPoint: centers[0], window: nil, display: display, padding: padding)]
        }
        return zip(frames, centers).map { frame, center in
            cropRect(element: frame, clickPoint: center, window: nil, display: displayFor(center), padding: padding)
        }
    }

    /// CG-space rect → the same rect relative to one display's top-left, in points.
    static func displayLocalRect(_ r: CGRect, inDisplay display: CGRect) -> CGRect {
        r.offsetBy(dx: -display.minX, dy: -display.minY)
    }

    /// CG-space rect → display-local pixels.
    static func pixelRect(_ r: CGRect, inDisplay display: CGRect, scale: CGFloat) -> CGRect {
        let local = displayLocalRect(r, inDisplay: display)
        return CGRect(x: local.minX * scale, y: local.minY * scale, width: local.width * scale, height: local.height * scale)
    }

    // MARK: Window hit-test (R3)

    struct WindowRecord: Sendable, Equatable, Codable {
        var ownerPID: pid_t
        var layer: Int
        var bounds: CGRect
    }

    /// Topmost normal-layer window under `point`, skipping Locant's own. `windows` is front to back.
    /// This is what Snap and Cut take on a click, and the crop clamp when no element answered.
    static func windowOwner(at point: CGPoint, windows: [WindowRecord], excludingPID: pid_t) -> WindowRecord? {
        windows.first { $0.layer == 0 && $0.ownerPID != excludingPID && $0.bounds.contains(point) }
    }

    /// Every on-screen window under `point` in any layer, front to back, skipping Locant's own. The
    /// first is what the user sees there; the ones behind it matter only when its owner reports
    /// nothing at the point. The Dock, the menu bar, and the Finder desktop each own a screen-wide
    /// window that is mostly empty, so a desktop icon, a widget, or a status item is reached by
    /// asking each owner in turn (see `AccessibilityReader.snapshot(at:candidates:fallbackPID:)`).
    static func windowCandidates(at point: CGPoint, windows: [WindowRecord], excludingPID: pid_t) -> [WindowRecord] {
        windows.filter { $0.ownerPID != excludingPID && $0.bounds.contains(point) }
    }

    /// Whether an owner's answer to a hit test at `point` is what shows there. An app hit-tests all
    /// of its own windows, and its menu bar, wherever they sit among other apps' windows; asked
    /// because of a transparent panel (Wispr Flow keeps one over the left of the screen), it answers
    /// with its menu bar, or with an element of its own window behind someone else's. Not at the
    /// point: a frame that does not hold it, or a window (`window`, the element's own) that another
    /// app's normal window covers there. What cannot be read stands.
    static func answerIsVisible(frame: CGRect?, window: CGRect?, owner: pid_t, at point: CGPoint,
                                candidates: [WindowRecord], tolerance: Double = HitRefiner.tolerance) -> Bool {
        if let frame, frame.width > 0, frame.height > 0, !frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point) {
            return false
        }
        guard let window,
              let index = candidates.firstIndex(where: { $0.ownerPID == owner && matches($0.bounds, window) }) else { return true }
        return !candidates[..<index].contains { $0.layer == 0 && $0.ownerPID != owner }
    }

    /// The same window, read once from the window list and once through accessibility.
    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }
}
