import CoreGraphics
import Foundation

/// Raw attributes of one accessibility node, as read from the platform or recorded in a fixture.
/// Keys are the platform attribute names so fixtures read like real accessibility dumps.
struct AttributeSet: Codable, Sendable, Equatable {
    var role: String?
    var subrole: String?
    var title: String?
    var description: String?
    var value: ElementValue?
    var identifier: String?
    var frame: Frame?
    var childCount: Int?
    /// v0.8: the DOM id and class list WebKit and Chromium publish for web nodes. `domClasses` is
    /// non-nil (possibly empty) exactly when the node is a web node.
    var domId: String? = nil
    var domClasses: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case role = "AXRole"
        case subrole = "AXSubrole"
        case title = "AXTitle"
        case description = "AXDescription"
        case value = "AXValue"
        case identifier = "AXIdentifier"
        case frame = "AXFrame"
        case childCount = "AXChildrenCount"
        case domId = "AXDOMIdentifier"
        case domClasses = "AXDOMClassList"
    }

    /// True for a node of a web page or an Electron renderer.
    var isWebNode: Bool { domClasses != nil || domId != nil }

    /// `#id`, else `.firstClass`, else nil: the DOM handle a path segment shows.
    var domHandle: String? {
        if let id = ElementResolver.nonEmpty(domId) { return "#" + id }
        if let first = domClasses?.first(where: { !$0.isEmpty }) { return "." + first }
        return nil
    }
}

/// The hit element plus its ancestor chain, nearest first, as walked through the parent attribute.
struct ElementSnapshot: Codable, Sendable, Equatable {
    var element: AttributeSet
    var ancestors: [AttributeSet]
    /// Direct children, read only when the element is a window-spanning container (flat trees).
    var children: [AttributeSet]? = nil
    /// The parent's children (including this element), read only when the parent spans the window.
    var siblings: [AttributeSet]? = nil
    /// The on-screen window whose owner answered the hit test (R3). Not part of fixtures.
    var window: Geometry.WindowRecord? = nil
    /// v0.8: the page address, read from the web area above a web node. Nil elsewhere.
    var url: String? = nil
}

/// Something that can hit-test a screen point and return a snapshot. The app's provider is the
/// accessibility actor; tests use scripted stand-ins.
protocol ElementProvider: Sendable {
    func snapshot(at point: CGPoint) async -> ElementSnapshot?
}

/// Pure transform from a snapshot to the platform-neutral element (R3, section 4).
enum ElementResolver {
    static let maxAncestors = 6

    static func resolve(_ snapshot: ElementSnapshot) -> ResolvedElement? {
        // A missing or empty frame means the element cannot be cropped or pointed at. Never fabricate one.
        guard let frame = snapshot.element.frame, frame.w > 0, frame.h > 0 else { return nil }
        let rawRole = snapshot.element.role ?? ""
        let role = mapRole(rawRole, subrole: snapshot.element.subrole)
        let identifier = nonEmpty(snapshot.element.identifier)
        let label = nonEmpty(snapshot.element.title) ?? nonEmpty(snapshot.element.description)

        var path: [PathEntry] = snapshot.ancestors.prefix(maxAncestors).reversed().map { node in
            let nodeIdentifier = nonEmpty(node.identifier)
            return PathEntry(role: mapRole(node.role ?? "", subrole: node.subrole), identifier: nodeIdentifier,
                             dom: nodeIdentifier == nil ? node.domHandle : nil)
        }
        path.append(PathEntry(role: role, identifier: identifier, dom: identifier == nil ? snapshot.element.domHandle : nil))

        // v0.8: web nodes carry the DOM's handles beside the accessibility identifier.
        let dom: DOMInfo? = snapshot.element.isWebNode
            ? DOMInfo(id: nonEmpty(snapshot.element.domId), classes: (snapshot.element.domClasses ?? []).filter { !$0.isEmpty })
            : nil

        return ResolvedElement(
            role: role,
            rawRole: rawRole,
            label: label,
            identifier: identifier,
            identifierSource: identifierSource(role: role, identifier: identifier),
            value: snapshot.element.value,
            frame: frame,
            path: path,
            dom: dom
        )
    }

    /// Section 4: `possiblySymbolName` when role is image and the identifier looks like an SF Symbol name.
    static func identifierSource(role: String, identifier: String?) -> IdentifierSource {
        guard let identifier, !identifier.isEmpty else { return .unknown }
        if role == "image", looksLikeSymbolName(identifier) { return .possiblySymbolName }
        return .declared
    }

    /// `^[a-z0-9]+(\.[a-z0-9]+)*$` without a regex, so it stays trivially Sendable.
    static func looksLikeSymbolName(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        for segment in s.split(separator: ".", omittingEmptySubsequences: false) {
            if segment.isEmpty { return false }
            for scalar in segment.unicodeScalars {
                let ok = (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
                if !ok { return false }
            }
        }
        return true
    }

    /// Roles that lay out other elements. A hit on one of these is refined toward a real control
    /// near the cursor before it is shown (R2 hover precision).
    static let containerRoles: Set<String> = [
        "application", "window", "sheet", "drawer", "group", "splitGroup", "tabGroup", "toolbar",
        "scrollArea", "list", "table", "outline", "webArea", "layoutArea", "row", "column", "cell", "menuBar",
    ]

    static func isContainer(_ node: AttributeSet) -> Bool {
        containerRoles.contains(mapRole(node.role ?? "", subrole: node.subrole))
    }

    static let clusterRole = "cluster"
    static let clusterRawRole = "LocantCluster"

    /// A visual grouping computed from neighbouring elements. SwiftUI exposes leaves but not the
    /// cards that hold them; this stands in for the missing container and says so in its role.
    static func clusterElement(members: [AttributeSet], ancestors: [AttributeSet], within container: Frame? = nil) -> ResolvedElement? {
        let framed = members.filter { ($0.frame?.w ?? 0) > 0 && ($0.frame?.h ?? 0) > 0 }
        guard framed.count >= 2 else { return nil }
        // The members' bounds plus a typical card inset, kept inside the container: the visible card
        // is usually a little larger than what it holds.
        var union = HitRefiner.union(of: framed).insetBy(dx: -HitRefiner.clusterPadding, dy: -HitRefiner.clusterPadding)
        if let container = container?.cgRect, !union.intersection(container).isEmpty {
            union = union.intersection(container)
        }
        let ordered = framed.sorted { a, b in
            let fa = a.frame!, fb = b.frame!
            return abs(fa.y - fb.y) > 4 ? fa.y < fb.y : fa.x < fb.x
        }
        var path: [PathEntry] = ancestors.prefix(maxAncestors).reversed().map { node in
            PathEntry(role: mapRole(node.role ?? "", subrole: node.subrole), identifier: nonEmpty(node.identifier))
        }
        path.append(PathEntry(role: clusterRole, identifier: nil))
        return ResolvedElement(
            role: clusterRole,
            rawRole: clusterRawRole,
            label: nil,
            identifier: nil,
            identifierSource: .unknown,
            value: nil,
            frame: Frame(union),
            path: path,
            members: ordered.map { node in
                ElementMember(
                    role: mapRole(node.role ?? "", subrole: node.subrole),
                    label: nonEmpty(node.title) ?? nonEmpty(node.description),
                    identifier: nonEmpty(node.identifier)
                )
            }
        )
    }

    /// A group with no children is the lazy-tree symptom observed in the Simulator on first read.
    static func isEmptyGroup(_ snapshot: ElementSnapshot) -> Bool {
        mapRole(snapshot.element.role ?? "", subrole: snapshot.element.subrole) == "group"
            && (snapshot.element.childCount ?? 0) == 0
    }

    private static let roleMap: [String: String] = [
        "AXApplication": "application",
        "AXWindow": "window",
        "AXSheet": "sheet",
        "AXDrawer": "drawer",
        "AXGroup": "group",
        "AXSplitGroup": "splitGroup",
        "AXTabGroup": "tabGroup",
        "AXToolbar": "toolbar",
        "AXNavigationBar": "navigationBar",
        "AXButton": "button",
        "AXPopUpButton": "popUpButton",
        "AXMenuButton": "menuButton",
        "AXCheckBox": "checkBox",
        "AXRadioButton": "radioButton",
        "AXRadioGroup": "radioGroup",
        "AXDisclosureTriangle": "disclosureTriangle",
        "AXSlider": "slider",
        "AXIncrementor": "stepper",
        "AXProgressIndicator": "progressIndicator",
        "AXTextField": "textField",
        "AXTextArea": "textArea",
        "AXComboBox": "comboBox",
        "AXStaticText": "staticText",
        "AXHeading": "heading",
        "AXLink": "link",
        "AXImage": "image",
        "AXList": "list",
        "AXTable": "table",
        "AXOutline": "outline",
        "AXRow": "row",
        "AXColumn": "column",
        "AXCell": "cell",
        "AXScrollArea": "scrollArea",
        "AXScrollBar": "scrollBar",
        "AXMenuBar": "menuBar",
        "AXMenuBarItem": "menuBarItem",
        "AXMenu": "menu",
        "AXMenuItem": "menuItem",
        "AXDockItem": "dockItem",
        "AXWebArea": "webArea",
        "AXValueIndicator": "valueIndicator",
        "AXLayoutArea": "layoutArea",
        "AXUnknown": "unknown",
    ]

    private static let subroleMap: [String: String] = [
        "AXSwitch": "switch",
        "AXToggle": "toggle",
        "AXSearchField": "searchField",
        "AXSecureTextField": "secureTextField",
        "AXTabButton": "tab",
        "AXCloseButton": "closeButton",
        "AXMenuExtra": "menuExtra",
    ]

    /// Maps a platform role (and subrole, when it is more specific) to the platform-neutral vocabulary.
    static func mapRole(_ axRole: String, subrole: String?) -> String {
        if let subrole, let mapped = subroleMap[subrole] { return mapped }
        return roleMap[axRole] ?? "unknown"
    }

    static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}

extension ElementResolver {
    /// R3 lazy-tree retry: a nil hit or an empty group is re-read every `delay`, up to `retries` more
    /// times. A container hit on the first read is re-read once too, because Chromium answers the
    /// first hit test from a cache and refines it asynchronously; the container is kept as the
    /// fallback. Returns nil when no populated element was ever seen; the caller records `element: null`.
    static func resolve(
        at point: CGPoint,
        using provider: some ElementProvider,
        retries: Int = 5,
        delay: Duration = .milliseconds(100)
    ) async -> ResolvedElement? {
        await snapshotWithRetry(at: point, using: provider, retries: retries, delay: delay).flatMap(resolve)
    }

    /// The retry loop itself, for callers that need the snapshot (selection levels, clusters).
    static func snapshotWithRetry(
        at point: CGPoint,
        using provider: some ElementProvider,
        retries: Int = 5,
        delay: Duration = .milliseconds(100)
    ) async -> ElementSnapshot? {
        var fallback: ElementSnapshot?
        for attempt in 0...max(retries, 0) {
            if let snapshot = await provider.snapshot(at: point), !isEmptyGroup(snapshot), resolve(snapshot) != nil {
                if attempt == 0, isContainer(snapshot.element), retries > 0 {
                    fallback = snapshot
                } else {
                    return snapshot
                }
            }
            if (attempt < retries) && (delay > .zero) {
                try? await Task.sleep(for: delay)
            }
        }
        return fallback
    }
}

/// R2 hover precision. The platform hit test returns the deepest element under the point, and in
/// SwiftUI every gap between controls belongs to a window-sized group, so plain hovering flickers
/// between a small control and the whole screen. These rules keep the small one.
enum HitRefiner {
    /// A control counts as "under the cursor" when its frame grown by this much contains the point.
    static let tolerance: Double = 8
    /// The last small element stays selected while the cursor is within this distance of its frame.
    static let stickiness: Double = 12

    /// v0.9 R77: Snap and Cut end their ladder in the window. Empty rungs go; the window (role
    /// `window`, the app's name as its label, the window's bounds) is appended unless the top rung
    /// already spans it. No window (the desktop, the menu bar, the Dock): the elements alone. No
    /// elements (a canvas, Figma): the window alone.
    static func addingWindow(_ levels: [ResolvedElement?], window: CGRect?, appName: String?) -> [ResolvedElement?] {
        let rungs = levels.compactMap { $0 }
        guard let window, window.width > 0, window.height > 0 else { return rungs }
        // Only a rung that is the window itself stands in for it; a content group that covers most
        // of the window is not the window (it lacks the title bar and the toolbar).
        if let top = rungs.last, matches(top.frame, Frame(window)) { return rungs }
        let element = ResolvedElement(
            role: "window", rawRole: "AXWindow", label: appName, identifier: nil, identifierSource: .unknown,
            value: nil, frame: Frame(window), path: [PathEntry(role: "window", identifier: nil)]
        )
        return rungs + [element]
    }

    /// Among descendants of a container hit, the best replacement: smallest area, real controls
    /// before containers, and only if smaller than the container itself. Nil means the container
    /// stands (blank area or edge).
    static func choose(from candidates: [AttributeSet], replacing base: AttributeSet, at point: CGPoint,
                       tolerance: Double = tolerance) -> AttributeSet? {
        let baseArea = base.frame.map { $0.w * $0.h } ?? .infinity
        var best: (node: AttributeSet, area: Double, isContainer: Bool)?
        for candidate in candidates {
            guard let frame = candidate.frame, frame.w > 0, frame.h > 0,
                  frame.cgRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }
            let area = frame.w * frame.h
            guard area < baseArea else { continue }
            let isContainer = ElementResolver.isContainer(candidate)
            if let current = best {
                let wins = (!isContainer && current.isContainer) || (isContainer == current.isContainer && area < current.area)
                if wins { best = (candidate, area, isContainer) }
            } else {
                best = (candidate, area, isContainer)
            }
        }
        return best?.node
    }

    /// True when the previously shown element should stay: it is a real control and the cursor is
    /// still within `stickiness` of its frame.
    static func sticks(_ previous: ResolvedElement?, to point: CGPoint) -> Bool {
        guard let previous, !ElementResolver.containerRoles.contains(previous.role) else { return false }
        return previous.frame.cgRect.insetBy(dx: -stickiness, dy: -stickiness).contains(point)
    }

    /// Two frames belong to one visual cluster when one, grown by this much, touches the other.
    static let clusterGap: Double = 24
    /// A cluster's frame is its members' bounds grown by this much, a typical card inset.
    static let clusterPadding: Double = 16
    /// A container spans its window when it covers at least this share of it.
    static let spanningFraction: Double = 0.5
    /// A child covering at least this share of its container is a background, not content.
    static let backgroundFraction: Double = 0.6

    static func union(of nodes: [AttributeSet]) -> CGRect {
        nodes.compactMap { $0.frame?.cgRect }.reduce(CGRect.null) { $0.union($1) }
    }

    /// Connected components by proximity.
    static func clusters(among nodes: [AttributeSet], gap: Double = clusterGap) -> [[AttributeSet]] {
        let frames = nodes.map { $0.frame?.cgRect }
        var assigned = Array(repeating: false, count: nodes.count)
        var groups: [[AttributeSet]] = []
        for start in nodes.indices where !assigned[start] {
            guard let f = frames[start], f.width > 0, f.height > 0 else { continue }
            assigned[start] = true
            var group = [nodes[start]]
            var queue = [start]
            while let current = queue.popLast() {
                let grown = frames[current]!.insetBy(dx: -gap, dy: -gap)
                for other in nodes.indices where !assigned[other] {
                    guard let g = frames[other], g.width > 0, g.height > 0, grown.intersects(g) else { continue }
                    assigned[other] = true
                    group.append(nodes[other])
                    queue.append(other)
                }
            }
            groups.append(group)
        }
        return groups
    }

    /// The smallest cluster whose bounding box contains the point.
    static func cluster(containing point: CGPoint, among nodes: [AttributeSet]) -> [AttributeSet]? {
        clusters(among: nodes)
            .filter { union(of: $0).contains(point) }
            .min { area(union(of: $0)) < area(union(of: $1)) }
    }

    /// The cluster that contains `anchor` (by identity, else by its center).
    static func cluster(around anchor: AttributeSet, among nodes: [AttributeSet]) -> [AttributeSet]? {
        let groups = clusters(among: nodes)
        if let group = groups.first(where: { $0.contains(anchor) }) { return group }
        guard let f = anchor.frame?.cgRect else { return nil }
        return groups.first { union(of: $0).contains(CGPoint(x: f.midX, y: f.midY)) }
    }

    /// Framed nodes that are content rather than backgrounds of their container.
    static func content(of nodes: [AttributeSet], within container: Frame?) -> [AttributeSet] {
        let containerArea = container.map { $0.w * $0.h } ?? .infinity
        return nodes.filter { node in
            guard let f = node.frame, f.w > 0, f.h > 0 else { return false }
            return f.w * f.h < backgroundFraction * containerArea
        }
    }

    /// The same rectangle, within a point on every side.
    static func matches(_ a: Frame, _ b: Frame) -> Bool {
        abs(a.x - b.x) <= 1 && abs(a.y - b.y) <= 1 && abs(a.w - b.w) <= 1 && abs(a.h - b.h) <= 1
    }

    static func spans(_ frame: Frame?, window: Frame?) -> Bool {
        guard let frame, let window, window.w > 0, window.h > 0 else { return false }
        return frame.w * frame.h >= spanningFraction * window.w * window.h
    }

    /// The window the hit sits in. Some trees have none: the Finder desktop is a scroll area straight
    /// under the application, the menu bar likewise. The outermost framed ancestor stands in, so a
    /// blank desktop is a spanning container (cluster or nothing) rather than a screen-sized element.
    static func windowFrame(in snapshot: ElementSnapshot) -> Frame? {
        let chain = [snapshot.element] + snapshot.ancestors
        if let window = chain.first(where: { ElementResolver.mapRole($0.role ?? "", subrole: $0.subrole) == "window" }) {
            return window.frame
        }
        return chain.last { ($0.frame?.w ?? 0) > 0 && ($0.frame?.h ?? 0) > 0 }?.frame
    }

    private static func area(_ r: CGRect) -> Double { r.isNull ? .infinity : r.width * r.height }

    /// What Option cycles through, innermost first. A nil level means "nothing specific here"
    /// (the fallback square, `element: null` on click). Ancestors without a usable frame are skipped,
    /// so the chain never ends in a phantom.
    static func selectionLevels(for snapshot: ElementSnapshot, at point: CGPoint) -> [ResolvedElement?] {
        let base = ElementResolver.resolve(snapshot)
        let window = windowFrame(in: snapshot)
        var levels: [ResolvedElement?] = []
        if let base, ElementResolver.containerRoles.contains(base.role), spans(snapshot.element.frame, window: window) {
            // Window-sized container under the cursor: the cluster around the point, else nothing.
            let nodes = content(of: snapshot.children ?? [], within: snapshot.element.frame)
            if let members = cluster(containing: point, among: nodes),
               let cluster = ElementResolver.clusterElement(members: members, ancestors: [snapshot.element] + snapshot.ancestors, within: snapshot.element.frame) {
                levels.append(cluster)
            } else {
                levels.append(nil)
            }
            levels.append(base)
        } else if let base {
            levels.append(base)
            if let siblings = snapshot.siblings, let parent = snapshot.ancestors.first, spans(parent.frame, window: window) {
                let nodes = content(of: siblings, within: parent.frame)
                let parentArea = parent.frame.map { $0.w * $0.h } ?? .infinity
                if let members = cluster(around: snapshot.element, among: nodes),
                   let cluster = ElementResolver.clusterElement(members: members, ancestors: snapshot.ancestors, within: parent.frame),
                   cluster.frame.w * cluster.frame.h < 0.9 * parentArea {
                    levels.append(cluster)
                }
            }
        } else {
            levels.append(nil)
        }
        if !snapshot.ancestors.isEmpty {
            for depth in 1...snapshot.ancestors.count {
                if let up = ancestor(of: snapshot, depth: depth), let resolved = ElementResolver.resolve(up) {
                    levels.append(resolved)
                }
            }
        }
        return levels
    }

    /// The snapshot re-rooted `depth` ancestors up (Option steps the selection to the parent).
    /// Depth 0 is the element itself; nil when there is no such ancestor.
    static func ancestor(of snapshot: ElementSnapshot, depth: Int) -> ElementSnapshot? {
        guard depth > 0 else { return snapshot }
        guard depth <= snapshot.ancestors.count else { return nil }
        return ElementSnapshot(element: snapshot.ancestors[depth - 1], ancestors: Array(snapshot.ancestors[depth...]))
    }
}
