import CoreGraphics

/// specs/ball-edges.md R80: where the ball may tuck on one screen, and how far in it must come for
/// the ring. Pure. Everything is in AppKit coordinates (bottom-left origin, y up), and every
/// position is the disc's center. Tucks use the screen's real edges, not `visibleFrame`: beside a
/// Dock at the bottom the bottom of the screen is free, over the Dock it is not.
struct BallEdges: Equatable, Sendable {
    enum Edge: CaseIterable, Sendable { case left, right, bottom }

    struct Tuck: Equatable, Sendable {
        var edge: Edge
        /// The disc's center, `dockedVisible` of the disc on screen.
        var center: CGPoint
    }

    typealias Span = ClosedRange<CGFloat>

    let frame: CGRect
    let visible: CGRect
    /// Along each edge, the stretches the center may tuck into: y on the sides, x on the bottom.
    let free: [Edge: [Span]]
    /// Along each edge, what the Dock covers widened by `dockGap`, or the whole edge when its span is unknown.
    let dockSpans: [Edge: [Span]]

    static var radius: CGFloat { FloatingBall.Tokens.diameter / 2 }
    /// How far inside its edge a tucked center sits: 4.8 pt, so 60 percent of the disc shows.
    static var tuckInset: CGFloat { FloatingBall.Tokens.diameter * FloatingBall.Tokens.dockedVisible - radius }
    /// The wake radius: tucked this far from the Dock's ends, the ball sleeps while the cursor reaches for them.
    static var dockGap: CGFloat { FloatingBall.Tokens.approach }
    static var cornerMargin: CGFloat { FloatingBall.Tokens.diameter }
    /// With no Dock frame, `visibleFrame` inset more than this from an edge means the Dock is on it.
    static let dockInset: CGFloat = 8

    /// `dock`: the Dock's tiles, wherever they are; they count when this screen is the one nearest them.
    /// `others`: the other screens' frames.
    init(frame: CGRect, visible: CGRect, dock: CGRect?, others: [CGRect]) {
        self.frame = frame
        self.visible = visible
        var dockSpans: [Edge: [Span]] = [:]
        if let dock {
            if Self.isNearest(frame, to: dock, among: others) {
                let (edge, span) = Self.dockEdge(dock, in: frame)
                dockSpans[edge] = [(span.lowerBound - Self.dockGap)...(span.upperBound + Self.dockGap)]
            }
        } else {
            if visible.minY - frame.minY > Self.dockInset { dockSpans[.bottom] = [Self.length(of: .bottom, frame: frame, visible: visible)] }
            if visible.minX - frame.minX > Self.dockInset { dockSpans[.left] = [Self.length(of: .left, frame: frame, visible: visible)] }
            if frame.maxX - visible.maxX > Self.dockInset { dockSpans[.right] = [Self.length(of: .right, frame: frame, visible: visible)] }
        }
        var free: [Edge: [Span]] = [:]
        for edge in Edge.allCases {
            let whole = Self.length(of: edge, frame: frame, visible: visible)
            guard let usable = Self.span(whole.lowerBound + Self.cornerMargin, whole.upperBound - Self.cornerMargin) else {
                free[edge] = []
                continue
            }
            let cuts = (dockSpans[edge] ?? []) + others.compactMap { Self.shared(edge, with: $0, frame: frame) }
            free[edge] = Self.subtract(cuts, from: usable)
        }
        self.free = free
        self.dockSpans = dockSpans
    }

    // MARK: Questions

    /// The free tuck nearest `point`, or nil when no edge has room.
    func tuck(nearest point: CGPoint) -> Tuck? {
        var best: (tuck: Tuck, distance: CGFloat)?
        for edge in Edge.allCases {
            for span in free[edge] ?? [] {
                let along = edge == .bottom ? point.x : point.y
                let candidate = tuck(on: edge, at: min(max(along, span.lowerBound), span.upperBound))
                let distance = hypot(candidate.center.x - point.x, candidate.center.y - point.y)
                if distance < best?.distance ?? .infinity { best = (candidate, distance) }
            }
        }
        return best?.tuck
    }

    /// The tuck's spot with the whole disc on screen, touching the edge: the ball's home while it rests there.
    func home(for tuck: Tuck) -> CGPoint {
        switch tuck.edge {
        case .left: CGPoint(x: frame.minX + Self.radius, y: tuck.center.y)
        case .right: CGPoint(x: frame.maxX - Self.radius, y: tuck.center.y)
        case .bottom: CGPoint(x: tuck.center.x, y: frame.minY + Self.radius)
        }
    }

    /// A drop here tucks: within `edgeSnap` of the left, right, or bottom of `visibleFrame`, or past it.
    func isNearEdge(_ point: CGPoint) -> Bool {
        let snap = FloatingBall.Tokens.edgeSnap
        return point.x - visible.minX <= snap || visible.maxX - point.x <= snap || point.y - visible.minY <= snap
    }

    /// `center` pulled in until the ring (`ringMargin`) fits. Toward the menu bar it measures from
    /// `visibleFrame`; toward the other sides from the real edge, except across the Dock.
    func ringSafe(_ center: CGPoint) -> CGPoint {
        let margin = FloatingBall.Tokens.ringMargin
        let left = (covered(.left, at: center.y) ? visible.minX : frame.minX) + margin
        let right = (covered(.right, at: center.y) ? visible.maxX : frame.maxX) - margin
        let bottom = (covered(.bottom, at: center.x) ? visible.minY : frame.minY) + margin
        let top = visible.maxY - margin
        guard left <= right, bottom <= top else { return center }
        return CGPoint(x: min(max(center.x, left), right), y: min(max(center.y, bottom), top))
    }

    /// `point` kept inside `visibleFrame` with the whole disc showing: where a throw into open space rests.
    func inside(_ point: CGPoint) -> CGPoint {
        let area = visible.insetBy(dx: Self.radius, dy: Self.radius)
        guard !area.isNull else { return point }
        return CGPoint(x: min(max(point.x, area.minX), area.maxX), y: min(max(point.y, area.minY), area.maxY))
    }

    // MARK: Pieces

    private func tuck(on edge: Edge, at along: CGFloat) -> Tuck {
        switch edge {
        case .left: Tuck(edge: edge, center: CGPoint(x: frame.minX + Self.tuckInset, y: along))
        case .right: Tuck(edge: edge, center: CGPoint(x: frame.maxX - Self.tuckInset, y: along))
        case .bottom: Tuck(edge: edge, center: CGPoint(x: along, y: frame.minY + Self.tuckInset))
        }
    }

    private func covered(_ edge: Edge, at along: CGFloat) -> Bool {
        (dockSpans[edge] ?? []).contains { $0.contains(along) }
    }

    /// The whole stretch of an edge the center could use; the sides run up to the menu bar.
    private static func length(of edge: Edge, frame: CGRect, visible: CGRect) -> Span {
        switch edge {
        case .left, .right: frame.minY...max(frame.minY, visible.maxY)
        case .bottom: frame.minX...frame.maxX
        }
    }

    /// A Dock wider than tall is on the bottom; otherwise on the side its middle is nearer. Its span runs along that edge.
    private static func dockEdge(_ dock: CGRect, in frame: CGRect) -> (Edge, Span) {
        if dock.width > dock.height { return (.bottom, dock.minX...dock.maxX) }
        return (dock.midX < frame.midX ? .left : .right, dock.minY...dock.maxY)
    }

    private static func isNearest(_ frame: CGRect, to dock: CGRect, among others: [CGRect]) -> Bool {
        let middle = CGPoint(x: dock.midX, y: dock.midY)
        let mine = distance(from: middle, to: frame)
        return others.allSatisfy { mine <= distance(from: middle, to: $0) }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
    }

    /// Where `other` touches this screen along `edge`, widened by a radius so no part of a tucked disc
    /// shows on the other display; nil when it does not touch.
    private static func shared(_ edge: Edge, with other: CGRect, frame: CGRect) -> Span? {
        let touching: Bool
        let overlap: (low: CGFloat, high: CGFloat)
        switch edge {
        case .left:
            touching = abs(other.maxX - frame.minX) <= 1
            overlap = (max(frame.minY, other.minY), min(frame.maxY, other.maxY))
        case .right:
            touching = abs(other.minX - frame.maxX) <= 1
            overlap = (max(frame.minY, other.minY), min(frame.maxY, other.maxY))
        case .bottom:
            touching = abs(other.maxY - frame.minY) <= 1
            overlap = (max(frame.minX, other.minX), min(frame.maxX, other.maxX))
        }
        guard touching, overlap.low < overlap.high else { return nil }
        return (overlap.low - radius)...(overlap.high + radius)
    }

    /// `range` with every one of `cuts` taken out; what is left, low to high.
    private static func subtract(_ cuts: [Span], from range: Span) -> [Span] {
        var pieces: [Span] = []
        var low = range.lowerBound
        for cut in cuts.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let piece = span(low, min(cut.lowerBound, range.upperBound)) { pieces.append(piece) }
            low = max(low, cut.upperBound)
        }
        if let piece = span(low, range.upperBound) { pieces.append(piece) }
        return pieces
    }

    private static func span(_ low: CGFloat, _ high: CGFloat) -> Span? {
        low < high ? low...high : nil
    }
}
