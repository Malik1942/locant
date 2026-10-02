import AppKit
import QuartzCore

/// A spring in SwiftUI's terms: `response` is the period of one swing in seconds, `damping` the
/// fraction of critical damping (1 settles with no overshoot). Pure; `Glide` drives it.
struct Spring: Sendable, Equatable {
    var response: Double
    var damping: Double

    /// The system's default spring (SwiftUI `.spring`): a slight overshoot that settles at once.
    static let wake = Spring(response: 0.5, damping: 0.825)
    /// Settling back to where it rested.
    static let settle = Spring(response: 0.45, damping: 0.9)
    /// Tucking into an edge.
    static let tuck = Spring(response: 0.4, damping: 0.95)
    /// Hover and the hand: quick and critically damped, so nothing bounces under the cursor.
    static let hover = Spring(response: 0.32, damping: 1.0)

    /// The same spring for a Core Animation layer: stiffness and damping for unit mass.
    var stiffness: CGFloat { let omega = 2 * Double.pi / response; return omega * omega }
    var dampingCoefficient: CGFloat { 2 * damping * 2 * Double.pi / response }

    /// Progress at `t` seconds: 0 at the start, past 1 while overshooting, 1 at rest.
    func value(at t: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        let zeta = min(damping, 0.999)
        let omegaD = omega * (1 - zeta * zeta).squareRoot()
        let decay = exp(-zeta * omega * t)
        return 1 - decay * (cos(omegaD * t) + (zeta * omega / omegaD) * sin(omegaD * t))
    }

    /// The offset from rest after `t` seconds, in the caller's units, of a spring let go
    /// `displacement` from rest while moving at `velocity` per second. With no velocity it is
    /// `displacement · (1 − value(at: t))`; a velocity is how a thrown ball keeps the hand's speed.
    func offset(at t: Double, displacement: Double, velocity: Double) -> Double {
        guard t > 0 else { return displacement }
        let omega = 2 * Double.pi / response
        let zeta = min(damping, 0.999)
        let omegaD = omega * (1 - zeta * zeta).squareRoot()
        let decay = exp(-zeta * omega * t)
        return decay * (displacement * cos(omegaD * t) + (zeta * omega * displacement + velocity) / omegaD * sin(omegaD * t))
    }

    /// When `offset` stays within `tolerance` of rest: the swing's envelope has decayed that far.
    func settleTime(displacement: Double, velocity: Double, tolerance: Double = 0.25) -> Double {
        let omega = 2 * Double.pi / response
        let zeta = min(damping, 0.999)
        let omegaD = omega * (1 - zeta * zeta).squareRoot()
        let amplitude = hypot(displacement, (zeta * omega * displacement + velocity) / omegaD)
        guard amplitude > tolerance else { return 0 }
        return log(amplitude / tolerance) / (zeta * omega)
    }
}

/// Moves a window along a spring, one step per display refresh. Under Reduce Motion the window
/// goes straight to the target.
@MainActor
final class Glide {
    private let window: NSWindow
    private var link: CADisplayLink?
    private var from = CGPoint.zero
    private var to = CGPoint.zero
    private var velocity = CGPoint.zero
    private var spring = Spring.settle
    private var start: CFTimeInterval = 0
    private var duration: Double = 0

    init(window: NSWindow) {
        self.window = window
    }

    /// `velocity`, in points per second, is the window's speed as it is let go; a thrown ball keeps it.
    func move(to target: CGPoint, spring: Spring, velocity: CGPoint = .zero) {
        cancel()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.setFrameOrigin(target)
            return
        }
        from = window.frame.origin
        to = target
        self.velocity = velocity
        self.spring = spring
        start = CACurrentMediaTime()
        duration = max(spring.settleTime(displacement: from.x - to.x, velocity: velocity.x),
                       spring.settleTime(displacement: from.y - to.y, velocity: velocity.y))
        let link = window.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func cancel() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let t = CACurrentMediaTime() - start
        guard t < duration else {
            window.setFrameOrigin(to)
            cancel()
            return
        }
        window.setFrameOrigin(CGPoint(
            x: to.x + spring.offset(at: t, displacement: from.x - to.x, velocity: velocity.x),
            y: to.y + spring.offset(at: t, displacement: from.y - to.y, velocity: velocity.y)
        ))
    }
}

/// Scale about the center of `bounds`, for layer springs on AppKit-managed layers (anchor at the origin).
func centeredScale(_ scale: CGFloat, in bounds: CGRect) -> CATransform3D {
    var transform = CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0)
    transform = CATransform3DScale(transform, scale, scale, 1)
    return CATransform3DTranslate(transform, -bounds.midX, -bounds.midY, 0)
}
