import CoreGraphics
import Foundation

/// specs/ball-edges.md R88: what letting go of the ball does. A release faster than `minimumSpeed`
/// is a throw, carried on the way iOS carries Picture in Picture; anything slower is a drop. Pure.
enum Throw {
    struct Sample: Equatable, Sendable {
        var time: TimeInterval
        var point: CGPoint
    }

    struct Release: Equatable, Sendable {
        /// Where the disc's center comes to rest, or the point its tuck was chosen from.
        var landing: CGPoint
        var thrown: Bool
        /// Set when the release tucks the ball.
        var tuck: BallEdges.Tuck?
    }

    /// The speed is read over this much of the drag before the release.
    static let window: TimeInterval = 0.08
    static let minimumSpeed: CGFloat = 700
    /// A wilder flick counts as this fast.
    static let maximumSpeed: CGFloat = 4000
    /// UIScrollView's normal deceleration rate, per millisecond.
    static let deceleration: CGFloat = 0.998

    /// Points per second from the oldest sample within `window` of the last one to the last one.
    /// The release itself is the last sample, so a pause before letting go reads as still.
    static func velocity(_ samples: [Sample]) -> CGPoint {
        guard let last = samples.last,
              let first = samples.first(where: { last.time - $0.time <= window }),
              last.time > first.time else { return .zero }
        let elapsed = CGFloat(last.time - first.time)
        let velocity = CGPoint(x: (last.point.x - first.point.x) / elapsed, y: (last.point.y - first.point.y) / elapsed)
        let speed = hypot(velocity.x, velocity.y)
        guard speed > maximumSpeed else { return velocity }
        return CGPoint(x: velocity.x * maximumSpeed / speed, y: velocity.y * maximumSpeed / speed)
    }

    static func isThrow(_ velocity: CGPoint) -> Bool {
        hypot(velocity.x, velocity.y) >= minimumSpeed
    }

    /// How far the deceleration carries a release: `v · d / (1 − d)` with `d` per millisecond,
    /// about half a second of the velocity.
    static func projection(_ velocity: CGPoint) -> CGPoint {
        let seconds = deceleration / (1 - deceleration) / 1000
        return CGPoint(x: velocity.x * seconds, y: velocity.y * seconds)
    }

    /// `start` carried by `offset`, stopped where the path leaves `bounds`.
    static func landing(from start: CGPoint, by offset: CGPoint, in bounds: CGRect) -> CGPoint {
        let origin = CGPoint(x: min(max(start.x, bounds.minX), bounds.maxX), y: min(max(start.y, bounds.minY), bounds.maxY))
        var t: CGFloat = 1
        if offset.x > 0 { t = min(t, (bounds.maxX - origin.x) / offset.x) }
        if offset.x < 0 { t = min(t, (bounds.minX - origin.x) / offset.x) }
        if offset.y > 0 { t = min(t, (bounds.maxY - origin.y) / offset.y) }
        if offset.y < 0 { t = min(t, (bounds.minY - origin.y) / offset.y) }
        t = max(t, 0)
        return CGPoint(x: origin.x + offset.x * t, y: origin.y + offset.y * t)
    }

    /// Letting go of a disc centered at `center` and moving at `velocity`: where it lands, and the
    /// tuck when the landing is at an edge and Auto-hide is on. A throw into open space rests inside
    /// the visible frame; a drop stays exactly where it is.
    static func release(center: CGPoint, velocity: CGPoint, edges: BallEdges, autoHide: Bool) -> Release {
        guard isThrow(velocity) else {
            let tuck = autoHide && edges.isNearEdge(center) ? edges.tuck(nearest: center) : nil
            return Release(landing: center, thrown: false, tuck: tuck)
        }
        let point = landing(from: center, by: projection(velocity), in: edges.frame)
        if autoHide, edges.isNearEdge(point), let tuck = edges.tuck(nearest: point) {
            return Release(landing: point, thrown: true, tuck: tuck)
        }
        return Release(landing: edges.inside(point), thrown: true, tuck: nil)
    }
}
