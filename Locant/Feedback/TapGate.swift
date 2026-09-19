import CoreGraphics
import Foundation

/// v0.8.1 R59: at most one tap per `spacing`, measured from the last tap let through. A dropped
/// tap neither restarts the interval nor plays later, so a fast sweep is an even ratchet.
struct TapGate {
    let spacing: TimeInterval
    private var last: TimeInterval?

    init(spacing: TimeInterval) {
        self.spacing = spacing
    }

    mutating func admit(at now: TimeInterval) -> Bool {
        if let last, now - last < spacing { return false }
        last = now
        return true
    }

    /// Shuts the gate for `spacing` from `now`, as a tap would, without one: a click is felt already.
    mutating func hold(at now: TimeInterval) {
        last = now
    }
}

/// v0.8.1 R59: whether the drawn outline moved. The first outline after the overlay opens is not
/// a move, nor is one onto the no-element square (nil), nor a drift of `drift` or less on every
/// edge; leaving the square for an element is.
struct OutlineMoves {
    /// A web card lifting under the pointer shifts about this much.
    static let drift: CGFloat = 2
    private var drawn = false
    private var last: CGRect?

    mutating func moved(to frame: CGRect?) -> Bool {
        defer { drawn = true; last = frame }
        guard drawn, let frame else { return false }
        guard let last else { return true }
        return abs(frame.minX - last.minX) > Self.drift || abs(frame.minY - last.minY) > Self.drift
            || abs(frame.maxX - last.maxX) > Self.drift || abs(frame.maxY - last.maxY) > Self.drift
    }
}
