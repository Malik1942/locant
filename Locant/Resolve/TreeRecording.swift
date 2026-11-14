import CoreGraphics
import Foundation

/// specs/frozen-screen.md R174: the accessibility tree near the pointer as a session began, read before
/// the overlay opened. The overlay shows the screen as it was then (R119), but the app has moved on: what
/// it showed on hover has left its tree. Where a recorded node has left, the recording answers for it.
/// Pure and Sendable; the elements themselves stay in `AccessibilityReader`, which also says which nodes
/// have left.
struct TreeRecording: Sendable, Equatable {
    struct Node: Sendable, Equatable {
        /// As `AccessibilityReader.attributes(of:)` reads them: value, child count and DOM handles included.
        var attributes: AttributeSet
        /// A parent always comes before its children in `nodes`.
        var parent: Int?
        var depth: Int
        /// The children that were read, in the app's order. Fewer than `attributes.childCount` when the
        /// walk stopped early or did not go this far from the pointer.
        var children: [Int] = []
        /// The page address, on a web area.
        var url: String? = nil
    }

    var pid: pid_t
    var nodes: [Node] = []

    /// A node this far from the pointer is recorded, but what it holds is not.
    static let radius: Double = 600
    static let nodeLimit = 1500

    /// How far `frame` is from `point`: 0 inside it, and 0 for a node with no frame or an empty one (the
    /// application), which is always walked into.
    static func distance(from point: CGPoint, to frame: Frame?) -> Double {
        guard let frame, frame.w > 0, frame.h > 0 else { return 0 }
        let dx = max(frame.x - point.x, 0, point.x - (frame.x + frame.w))
        let dy = max(frame.y - point.y, 0, point.y - (frame.y + frame.h))
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Roles whose frame cuts off what they hold: a row scrolled out of a list still reports a frame, over
    /// whatever sits beside the list. Other parents do not clip; a hover menu hangs outside its item.
    private static let clippingRoles: Set<String> = ["window", "scrollArea", "webArea"]

    private static func clips(_ node: AttributeSet) -> Bool {
        clippingRoles.contains(ElementResolver.mapRole(node.role ?? "", subrole: node.subrole))
    }

    private static func holds(_ frame: Frame?, _ point: CGPoint) -> Bool {
        guard let frame, frame.w > 0, frame.h > 0 else { return false }
        return frame.cgRect.contains(point)
    }

    /// The recorded nodes whose frame holds `point`, the likeliest answer of a hit test first: deepest,
    /// then smallest, then last read. A node inside a window, scroll area or web area that does not hold
    /// the point is left out.
    func hits(at point: CGPoint) -> [Int] {
        var clipped = [Bool](repeating: false, count: nodes.count)
        var found: [Int] = []
        for (index, node) in nodes.enumerated() {
            if let parent = node.parent, clipped[parent] {
                clipped[index] = true
                continue
            }
            if Self.holds(node.attributes.frame, point) {
                found.append(index)
            } else if Self.clips(node.attributes), Self.distance(from: point, to: node.attributes.frame) > 0 {
                clipped[index] = true
            }
        }
        func area(_ index: Int) -> Double { nodes[index].attributes.frame.map { $0.w * $0.h } ?? .infinity }
        return found.sorted { a, b in
            if nodes[a].depth != nodes[b].depth { return nodes[a].depth > nodes[b].depth }
            if area(a) != area(b) { return area(a) < area(b) }
            return a > b
        }
    }

    /// Whether node `index` was what showed at a point, given the windows under that point as the session
    /// began, front to back. Not when a normal window lay in front of the node's own: the app's other
    /// window, or another app's. As in `Geometry.answerIsVisible`, what cannot be placed stands: a node
    /// outside any window (a menu bar item), or a window the list does not have at the point.
    func showed(_ index: Int, among candidates: [Geometry.WindowRecord]) -> Bool {
        var current: Int? = index
        var window: CGRect?
        while let node = current, window == nil {
            let attributes = nodes[node].attributes
            if ElementResolver.mapRole(attributes.role ?? "", subrole: attributes.subrole) == "window" { window = attributes.frame?.cgRect }
            current = nodes[node].parent
        }
        guard let window, let own = candidates.firstIndex(where: { $0.ownerPID == pid && Geometry.matches($0.bounds, window) }) else {
            return true
        }
        return !candidates[..<own].contains { $0.layer == 0 }
    }

    /// R2 hover precision, as `AccessibilityReader.refine` does it live: a container gives way to the best
    /// control among what it holds near the point.
    func refined(_ index: Int, at point: CGPoint) -> Int {
        let base = nodes[index]
        guard ElementResolver.isContainer(base.attributes) else { return index }
        let tolerance = HitRefiner.tolerance
        var candidates: [Int] = []
        var stack = base.children
        while let next = stack.popLast() {
            let node = nodes[next]
            guard node.depth - base.depth <= 12, let frame = node.attributes.frame,
                  frame.cgRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }
            candidates.append(next)
            if ElementResolver.isContainer(node.attributes) { stack.append(contentsOf: node.children) }
        }
        guard let chosen = HitRefiner.choose(from: candidates.map { nodes[$0].attributes }, replacing: base.attributes, at: point) else {
            return index
        }
        return candidates.first { nodes[$0].attributes == chosen } ?? index
    }

    /// What a live read keeps of an ancestor or a neighbor: no child count, the DOM handles only on the
    /// path of a web node, and no value, except the words of a text with no other name
    /// (specs/source-hints.md R158), as `AccessibilityReader.lightAttributes` reads them.
    private static func light(_ attributes: AttributeSet, web: Bool = false) -> AttributeSet {
        var light = attributes
        let unnamed = attributes.role == "AXStaticText" && (attributes.title ?? "").isEmpty && (attributes.description ?? "").isEmpty
        if !unnamed { light.value = nil }
        light.childCount = nil
        if !web {
            light.domId = nil
            light.domClasses = nil
        }
        return light
    }

    /// The snapshot a hover on node `index` would have read: the same shape as `AccessibilityReader.read`.
    func snapshot(of index: Int) -> ElementSnapshot {
        let node = nodes[index]
        let web = node.attributes.isWebNode
        var ancestors: [AttributeSet] = []
        var url: String? = node.url
        var current = node.parent
        while let up = current {
            if ancestors.count < ElementResolver.maxAncestors { ancestors.append(Self.light(nodes[up].attributes, web: web)) }
            if url == nil { url = nodes[up].url }
            current = nodes[up].parent
        }
        var snapshot = ElementSnapshot(element: node.attributes, ancestors: ancestors)
        snapshot.fromRecording = true
        if web { snapshot.url = url }
        func neighbors(_ indexes: [Int]) -> [AttributeSet] {
            indexes.prefix(AccessibilityReader.neighborLimit).map { Self.light(nodes[$0].attributes) }
        }
        if ElementResolver.isContainer(node.attributes) {
            snapshot.children = neighbors(node.children)
        } else if let parent = node.parent, ElementResolver.isContainer(nodes[parent].attributes) {
            snapshot.siblings = neighbors(nodes[parent].children)
        }
        return snapshot
    }

    /// Node `index` as the drawn-frame walk reports an element (`AccessibilityReader.elements(in:)`).
    func regionSnapshot(of index: Int) -> ElementSnapshot {
        var ancestors: [AttributeSet] = []
        var current = nodes[index].parent
        while let up = current, ancestors.count < ElementResolver.maxAncestors {
            ancestors.append(Self.light(nodes[up].attributes))
            current = nodes[up].parent
        }
        var snapshot = ElementSnapshot(element: Self.light(nodes[index].attributes), ancestors: ancestors)
        snapshot.fromRecording = true
        return snapshot
    }

    /// The nodes from the root down to `index`.
    func path(to index: Int) -> [Int] {
        var path = [index]
        while let parent = nodes[path[path.count - 1]].parent { path.append(parent) }
        return path.reversed()
    }

    /// What a drawn frame holds once the recording is counted: the recorded elements that have left the
    /// app, and the live ones that are not under them. `covers` are the frames of what left, outermost
    /// only; a live element inside one is behind it in the picture.
    static func merged(live: [ElementSnapshot], recorded: [ElementSnapshot], under covers: [CGRect]) -> [ElementSnapshot] {
        guard !recorded.isEmpty else { return live }
        let shown = live.filter { snapshot in
            guard let frame = snapshot.element.frame?.cgRect else { return true }
            return !covers.contains { $0.insetBy(dx: -1, dy: -1).contains(frame) }
        }
        return shown + recorded
    }
}
