import CoreGraphics
import Foundation

/// v0.6 R52: iterations are collected by themselves. After a Point capture in an app the user
/// builds, each launch or activation of that app within a day is a chance to capture the
/// element again. Pure: the decision, given the capture and the app that came forward.
enum AutoVerify {
    /// How long after a capture its app is watched.
    static let window: TimeInterval = 24 * 60 * 60
    /// The app has just come forward; let its window draw before the element is looked for.
    static let settle: Duration = .seconds(2)

    /// Whether `capture` is worth refinding when the app with `bundleId` came forward at `now`:
    /// it is the user's own app (mode fix), the same app, it has one element (not a drawn frame),
    /// that element is one accessibility can find again (not computed: a cluster, or a line of text read
    /// from the screen, specs/capture-shapes.md R127), so is each companion refound with it (no line: another
    /// element would be found in its place), and the capture is under a day old.
    static func wants(_ capture: Capture, activated bundleId: String, now: Date = .now) -> Bool {
        guard capture.mode == .fix, capture.source.app.bundleId == bundleId else { return false }
        guard let element = capture.element, element.role != ElementResolver.clusterRole,
              element.rawRole != ElementResolver.textRawRole,
              !companions(of: capture).contains(where: { $0.rawRole == ElementResolver.textRawRole }) else { return false }
        guard let created = ISO8601DateFormatter().date(from: capture.createdAt) else { return false }
        let age = now.timeIntervalSince(created)
        return age >= -60 && age <= window
    }

    /// specs/capture-shapes.md R126: the frame an iteration of `capture` is cut around, its element found again at
    /// `found`. On Device Hub's simulated screen (`screen`, from the tree the element was found in; nil elsewhere) a
    /// capture commits what is drawn inside the padded frame accessibility reports, so `found` is tightened by the
    /// ladder's rule (`HitRefiner.tightFrame(_:on:ink:)`), `ink` reading what is drawn from the crop just taken around
    /// it, and the two images show one outline. `found` as it is outside a simulator, for a set's shared image, and
    /// when the capture's frame is `found` itself: it committed the padded frame (clicked before the sample landed).
    static func afterFrame(of capture: Capture, found: CGRect, screen: CGRect?, ink: (CGRect) -> CGRect?) -> CGRect {
        guard capture.source.simulator != nil, !sharesOneImage(capture), let committed = capture.element?.frame,
              !HitRefiner.matches(committed, Frame(found)) else { return found }
        return HitRefiner.tightFrame(found, on: screen, ink: ink)
    }

    /// The image the next capture is compared with: the newest iteration, else the original.
    static func previousImagePath(of capture: Capture) -> String {
        capture.iterations.last?.imagePath ?? capture.image.path
    }

    /// The sidecar of the newest Point capture, or nil when the folder holds none. A set's extra
    /// crops ride in its own entry (v0.8 R58), so what marks a Point capture is the sidecar, not
    /// the number of files: Snap and Cut write an image and nothing else.
    static func newestSidecar(among entries: [LifecycleEntry]) -> URL? {
        entries
            .filter { $0.urls.contains { $0.pathExtension == "json" } }
            .max { $0.modified < $1.modified }?
            .urls.first { $0.pathExtension == "json" }
    }

    /// v0.8 R58: `capture.image` is `Geometry.cropRects(for:)[0]` — the union of a set whose
    /// elements fit one crop, or the first element's own crop when each got its own. Refinding the
    /// first element alone reproduces the baseline only in the second case; in the first, every
    /// element has to be found again before the crops can be compared.
    static func sharesOneImage(_ capture: Capture) -> Bool {
        guard let targets = capture.targets, targets.count > 1 else { return false }
        return targets.dropFirst().allSatisfy { $0.imagePath == nil }
    }

    /// The elements that have to be refound besides the first one before an iteration can be
    /// compared: a shared image's companions, and nothing otherwise.
    static func companions(of capture: Capture) -> [ResolvedElement] {
        guard sharesOneImage(capture) else { return [] }
        return (capture.targets ?? []).dropFirst().map(\.element)
    }
}
