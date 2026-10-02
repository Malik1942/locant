import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Owns every `AXUIElement`. Nothing accessibility-typed leaves this actor; callers receive
/// Sendable snapshots and the pure `ElementResolver` does the rest. Keeps AppKit off the main thread's
/// back: the overlay stays responsive while a lazy tree is being read.
actor AccessibilityReader {
    static let frameAttribute = "AXFrame"

    /// Accessibility trust for this process. `prompt` shows the system dialog once.
    nonisolated static func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Apps whose accessibility tree has been switched on this session (Electron and Chromium build
    /// it only when an assistive client asks).
    private var accessibilityEnabledPIDs: Set<pid_t> = []

    /// Chromium-based browsers respond to `AXEnhancedUserInterface`, the signal VoiceOver sends.
    /// Electron apps expose `AXManualAccessibility` for the same purpose and are detected by it.
    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta", "org.chromium.Chromium",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.vivaldi.Vivaldi",
    ]

    /// R3: Electron and Chromium apps expose only window-sized groups until accessibility is enabled
    /// from outside. Done once per app per session; the tree fills in within about half a second.
    private func enableAccessibilityIfNeeded(app: AXUIElement, pid: pid_t) {
        guard !accessibilityEnabledPIDs.contains(pid) else { return }
        accessibilityEnabledPIDs.insert(pid)
        var names: CFArray?
        AXUIElementCopyAttributeNames(app, &names)
        let attributeNames = (names as? [String]) ?? []
        if attributeNames.contains("AXManualAccessibility") {
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           Self.chromiumBundleIDs.contains(bundleID) {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    /// R3: the element under `point`, asked of the app that owns what the user sees there.
    /// `candidates` are the on-screen windows containing the point, front to back (see
    /// `Geometry.windowCandidates`). An owner that reports nothing at the point, or something that
    /// does not show there, yields to the window behind it: the Dock and the menu bar own screen-wide
    /// windows that are mostly empty, a transparent panel's owner answers from elsewhere, and the
    /// Finder desktop lies under everything. A normal window whose app reports nothing ends the
    /// search, since nothing behind it is visible; the system-wide element is the last resort there.
    /// With no candidate at all, `fallbackPID` (the app frontmost at hotkey time) is asked.
    /// The returned snapshot carries the window that answered.
    func snapshot(at point: CGPoint, candidates: [Geometry.WindowRecord], fallbackPID: pid_t) -> ElementSnapshot? {
        for window in candidates {
            if var snapshot = snapshot(at: point, pid: window.ownerPID, candidates: candidates) {
                snapshot.window = window
                return snapshot
            }
            if window.layer == 0 {
                guard var snapshot = systemWideSnapshot(at: point) else { return nil }
                snapshot.window = window
                return snapshot
            }
        }
        if fallbackPID > 0, let snapshot = snapshot(at: point, pid: fallbackPID) { return snapshot }
        return systemWideSnapshot(at: point)
    }

    /// Per-app hit test. Nil when the app has nothing at the point, or answers with something that
    /// does not show there (see `Geometry.answerIsVisible`).
    private func snapshot(at point: CGPoint, pid: pid_t, candidates: [Geometry.WindowRecord] = []) -> ElementSnapshot? {
        let app = AXUIElementCreateApplication(pid)
        enableAccessibilityIfNeeded(app: app, pid: pid)
        guard let element = hit(app, at: point) else { return nil }
        let window = self.element(copy(element, kAXWindowAttribute)).flatMap { frame(copy($0, Self.frameAttribute)) }
        guard Geometry.answerIsVisible(frame: frame(copy(element, Self.frameAttribute))?.cgRect, window: window?.cgRect,
                                       owner: pid, at: point, candidates: candidates) else { return nil }
        return snapshot(of: refine(element, at: point))
    }

    /// The system-wide hit test sees whatever is topmost, which under the overlay may be Locant
    /// itself; that answer is discarded.
    private func systemWideSnapshot(at point: CGPoint) -> ElementSnapshot? {
        guard let element = hit(AXUIElementCreateSystemWide(), at: point) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        return snapshot(of: refine(element, at: point))
    }

    /// R2 hover precision: a container hit is replaced by the best control among its descendants
    /// near the point (see `HitRefiner`). Descends only through nodes whose frame is near the point,
    /// so the walk stays small even on a large tree.
    private func refine(_ base: AXUIElement, at point: CGPoint) -> AXUIElement {
        let baseAttributes = attributes(of: base)
        guard ElementResolver.isContainer(baseAttributes) else { return base }
        let tolerance = HitRefiner.tolerance
        var candidates: [(element: AXUIElement, attributes: AttributeSet)] = []
        var stack: [(element: AXUIElement, depth: Int)] = []
        // First level: reuse the cached neighborhood when it lines up with the live children.
        let kids = children(of: base)
        let known = neighbors(of: base, attributes: baseAttributes)
        if known.count == kids.count {
            for (kid, attributes) in zip(kids, known) {
                guard let frame = attributes.frame, frame.cgRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }
                candidates.append((kid, attributes))
                if ElementResolver.isContainer(attributes) { stack.append((kid, 2)) }
            }
            stack = stack.flatMap { container in children(of: container.element).map { ($0, 2) } }
        } else {
            stack = kids.map { ($0, 1) }
        }
        var visited = 0
        while let (node, depth) = stack.popLast(), visited < 400 {
            visited += 1
            guard let frame = frame(copy(node, Self.frameAttribute)),
                  frame.cgRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }
            let nodeAttributes = lightAttributes(of: node)
            candidates.append((node, nodeAttributes))
            if depth < 12, ElementResolver.isContainer(nodeAttributes) {
                stack.append(contentsOf: children(of: node).map { ($0, depth + 1) })
            }
        }
        guard let chosen = HitRefiner.choose(from: candidates.map(\.attributes), replacing: baseAttributes, at: point),
              let match = candidates.first(where: { $0.attributes == chosen }) else { return base }
        return match.element
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = copy(element, kAXChildrenAttribute), let array = value as? [AnyObject] else { return [] }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    /// v0.2 R12: every element of the app whose frame touches `region`, with its ancestors, walking
    /// only through nodes that intersect the region. Frameless roots (the application) are descended.
    func elements(in region: CGRect, pid: pid_t) -> [ElementSnapshot] {
        let app = AXUIElementCreateApplication(pid)
        enableAccessibilityIfNeeded(app: app, pid: pid)
        var found: [ElementSnapshot] = []
        var visited = 0
        func walk(_ node: AXUIElement, ancestors: [AttributeSet], depth: Int) {
            guard visited < 800, depth < 14 else { return }
            visited += 1
            let frame = frame(copy(node, Self.frameAttribute))
            if let frame, frame.w > 0, frame.h > 0, !frame.cgRect.intersects(region) { return }
            let attributes = lightAttributes(of: node)
            if frame != nil, !ElementResolver.isContainer(attributes) {
                found.append(ElementSnapshot(element: attributes, ancestors: Array(ancestors.prefix(ElementResolver.maxAncestors))))
            }
            let nextAncestors = [attributes] + ancestors
            for child in children(of: node) {
                walk(child, ancestors: nextAncestors, depth: depth + 1)
            }
        }
        walk(app, ancestors: [], depth: 0)
        return found
    }

    /// Title of the app's focused window, falling back to its main window.
    func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        guard let window = element(copy(app, kAXFocusedWindowAttribute)) ?? element(copy(app, kAXMainWindowAttribute)) else {
            return nil
        }
        return string(copy(window, kAXTitleAttribute))
    }

    // MARK: Paste into the agent (v0.8.1 R63)

    /// Title of an agent app's focused window, for the note field's target label. A short messaging
    /// timeout, so an app that does not answer costs a quarter second rather than the system's six.
    func agentWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let window = element(copy(app, kAXFocusedWindowAttribute)) ?? element(copy(app, kAXMainWindowAttribute)) else {
            return nil
        }
        AXUIElementSetMessagingTimeout(window, 0.25)
        return string(copy(window, kAXTitleAttribute))
    }

    /// Brings an app forward through accessibility when `activate()` was not honored, as for a
    /// window on another Space: the app becomes frontmost and its main window is raised.
    func raise(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let window = element(copy(app, kAXMainWindowAttribute)) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }

    // MARK: The hand-off (specs/handoff.md R81–R83)

    /// R82: focus in the message box of the app's focused window. False when the only editable text
    /// there is a code editor, so a ⌘V would land in code. Usually the app already put focus back in
    /// its message box, and two reads settle it; otherwise the window is walked.
    func focusMessageBox(pid: pid_t) async -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        if let focused = element(copy(app, kAXFocusedUIElementAttribute)), isEditable(focused),
           !editableArea(focused).isCodeEditor {
            return true
        }
        guard let window = element(copy(app, kAXFocusedWindowAttribute)) ?? element(copy(app, kAXMainWindowAttribute)) else {
            return true
        }
        let found = editableAreas(in: window)
        let areas = found.map(\.area)
        switch AgentPaste.messageBox(in: areas) {
        case .focused, .unknown:
            return true
        case .onlyCodeEditor:
            return false
        case .focus(let index):
            let box = found[index].element
            AXUIElementSetAttributeValue(box, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            let took = await focusTakes(box)
            return AgentPaste.canPaste(focusTook: took, areas: areas)
        }
    }

    /// R82: Chromium applies a focus change a moment later (44 ms in Cursor on Oct 1, 2026; read back
    /// at once, it still says no), so the focus is read back every 40 ms for up to 400 ms, and once it
    /// took the page gets one more beat before the keys follow.
    private func focusTakes(_ element: AXUIElement) async -> Bool {
        for _ in 0..<10 {
            if (copy(element, kAXFocusedAttribute) as? Bool) == true {
                try? await Task.sleep(for: .milliseconds(60))
                return true
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    /// R83: whether the app's focused element takes an image paste (a message box, not code, not a
    /// terminal pane). False when nothing can be read.
    func focusTakesImagePaste(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let focused = element(copy(app, kAXFocusedUIElementAttribute)) else { return false }
        let classes = copy(focused, "AXDOMClassList") as? [String] ?? []
        return AgentPaste.takesImagePaste(editable: isEditable(focused), classes: classes, ancestorClasses: ancestorClasses(of: focused))
    }

    /// Chromium exposes a contenteditable message box as a text area.
    private static let editableRoles: Set<String> = [kAXTextAreaRole, kAXTextFieldRole]

    private func isEditable(_ element: AXUIElement) -> Bool {
        string(copy(element, kAXRoleAttribute)).map { Self.editableRoles.contains($0) } ?? false
    }

    /// An editable element's classes and its four nearest ancestors' (R82's code-editor test), its
    /// focus, and its bottom edge.
    private func editableArea(_ element: AXUIElement) -> AgentPaste.EditableArea {
        let classes = copy(element, "AXDOMClassList") as? [String] ?? []
        let ancestors = ancestorClasses(of: element)
        let frame = frame(copy(element, Self.frameAttribute))
        return AgentPaste.EditableArea(
            isFocused: (copy(element, kAXFocusedAttribute) as? Bool) == true,
            isCodeEditor: AgentPaste.isCodeEditor(classes: classes, ancestorClasses: ancestors),
            bottom: frame.map { $0.y + $0.h } ?? 0
        )
    }

    private func ancestorClasses(of element: AXUIElement) -> [[String]] {
        var ancestors: [[String]] = []
        var current = element
        for _ in 0..<4 {
            guard let parent = self.element(copy(current, kAXParentAttribute)) else { break }
            ancestors.append(copy(parent, "AXDOMClassList") as? [String] ?? [])
            current = parent
        }
        return ancestors
    }

    /// Every editable text area in a window, breadth first, at most 3000 nodes; an editable area's own
    /// children (its text) are not walked.
    private func editableAreas(in window: AXUIElement) -> [(element: AXUIElement, area: AgentPaste.EditableArea)] {
        var found: [(element: AXUIElement, area: AgentPaste.EditableArea)] = []
        var queue: [AXUIElement] = [window]
        var head = 0
        while head < queue.count, head < 3000 {
            let node = queue[head]
            head += 1
            if isEditable(node) {
                found.append((node, editableArea(node)))
                continue
            }
            queue.append(contentsOf: children(of: node))
        }
        return found
    }

    /// specs/ball-edges.md R86: the Dock's tiles (its `AXList`), in CG coordinates. Nil without the
    /// Dock, without trust, or without a list. A hidden Dock (a full-screen Space, auto-hide) reports
    /// a frame off the bottom of the screen; its span along the edge is still right.
    func dockFrame() -> CGRect? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let list = children(of: app).first { string(copy($0, kAXRoleAttribute)) == kAXListRole }
        return list.flatMap { frame(copy($0, Self.frameAttribute))?.cgRect }
    }

    // MARK: Reading

    private func hit(_ root: AXUIElement, at point: CGPoint) -> AXUIElement? {
        var out: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &out)
        return error == .success ? out : nil
    }

    private func snapshot(of element: AXUIElement) -> ElementSnapshot {
        let elementAttributes = attributes(of: element)
        // v0.8: a web node's ancestors are web nodes too; their DOM handles make the path grep-able.
        let web = elementAttributes.isWebNode
        var ancestors: [AttributeSet] = []
        var parents: [AXUIElement] = []
        var current = element
        for _ in 0..<ElementResolver.maxAncestors {
            guard let parent = self.element(copy(current, kAXParentAttribute)) else { break }
            parents.append(parent)
            ancestors.append(cachedAttributes(of: parent, web: web))
            current = parent
        }
        var snapshot = ElementSnapshot(element: elementAttributes, ancestors: ancestors)
        if web { snapshot.url = pageURL(above: current, pid: pidOf(element)) }
        // Flat trees (SwiftUI): read the neighbourhood so HitRefiner can form visual clusters.
        let window = HitRefiner.windowFrame(in: snapshot)
        if ElementResolver.isContainer(elementAttributes), HitRefiner.spans(elementAttributes.frame, window: window) {
            snapshot.children = neighbors(of: element, attributes: elementAttributes)
        } else if let parent = parents.first, let parentAttributes = ancestors.first,
                  HitRefiner.spans(parentAttributes.frame, window: window) {
            snapshot.siblings = neighbors(of: parent, attributes: parentAttributes)
        }
        return snapshot
    }

    // MARK: Attribute cache

    /// Reads cost about 2 ms each against the Simulator, and hover asks about the same ancestors
    /// dozens of times a second. Attributes are cached per element for `neighborTTL`.
    private struct ElementKey: Hashable {
        let pid: pid_t
        let hash: CFHashCode
    }

    private var attributeCache: [ElementKey: (stamp: ContinuousClock.Instant, attributes: AttributeSet)] = [:]

    private func cachedAttributes(of element: AXUIElement, web: Bool = false) -> AttributeSet {
        let key = ElementKey(pid: pidOf(element), hash: CFHash(element))
        let now = ContinuousClock.now
        if let cached = attributeCache[key], now - cached.stamp < Self.neighborTTL, !web || cached.attributes.domClasses != nil {
            return cached.attributes
        }
        var read = lightAttributes(of: element)
        if web { readDOM(of: element, into: &read) }
        if attributeCache.count > 256 { attributeCache.removeAll() }
        attributeCache[key] = (now, read)
        return read
    }

    private func pidOf(_ element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    // MARK: Web nodes (v0.8)

    /// The DOM id and class list, which WebKit and Chromium publish on every web node and nothing
    /// else has. `domClasses` becomes non-nil exactly when the node is a web node.
    private func readDOM(of element: AXUIElement, into attributes: inout AttributeSet) {
        if let classes = copy(element, "AXDOMClassList") as? [String] {
            attributes.domClasses = classes
            attributes.domId = string(copy(element, "AXDOMIdentifier"))
        } else if let id = string(copy(element, "AXDOMIdentifier")) {
            attributes.domClasses = []
            attributes.domId = id
        }
    }

    /// The page address, from the web area above a web node. DOM trees run deeper than the ancestors
    /// a snapshot keeps, so this climbs on its own, and the answer is cached per app for `neighborTTL`
    /// since hover asks for it many times a second.
    private var urlCache: [pid_t: (stamp: ContinuousClock.Instant, url: String?)] = [:]

    private func pageURL(above start: AXUIElement, pid: pid_t) -> String? {
        let now = ContinuousClock.now
        if let cached = urlCache[pid], now - cached.stamp < Self.neighborTTL { return cached.url }
        var url: String?
        var node: AXUIElement? = start
        for _ in 0..<60 {
            guard let current = node else { break }
            if string(copy(current, kAXRoleAttribute)) == "AXWebArea" {
                url = webURL(copy(current, "AXURL"))
                break
            }
            node = element(copy(current, kAXParentAttribute))
        }
        urlCache[pid] = (now, url)
        return url
    }

    private func webURL(_ value: CFTypeRef?) -> String? {
        guard let value else { return nil }
        if CFGetTypeID(value) == CFURLGetTypeID() { return ((value as! CFURL) as URL).absoluteString }
        return string(value)
    }

    // MARK: Neighborhood cache

    /// Hover moves inside one container far more often than that container's children change, so a
    /// container's children are re-read at most every `neighborTTL`. Keyed by app, role, and frame.
    private struct NeighborKey: Hashable {
        let pid: pid_t
        let role: String?
        let frame: Frame?
    }

    private var neighborCache: [NeighborKey: (stamp: ContinuousClock.Instant, nodes: [AttributeSet])] = [:]
    private static let neighborTTL: Duration = .milliseconds(400)
    private static let neighborLimit = 60

    private func neighbors(of container: AXUIElement, attributes: AttributeSet) -> [AttributeSet] {
        var pid: pid_t = 0
        AXUIElementGetPid(container, &pid)
        let key = NeighborKey(pid: pid, role: attributes.role, frame: attributes.frame)
        let now = ContinuousClock.now
        if let cached = neighborCache[key], now - cached.stamp < Self.neighborTTL {
            return cached.nodes
        }
        let nodes = children(of: container).prefix(Self.neighborLimit).map { lightAttributes(of: $0) }
        if neighborCache.count > 32 { neighborCache.removeAll() }
        neighborCache[key] = (now, nodes)
        return nodes
    }

    /// What clustering needs and nothing more: six reads instead of eight.
    private func lightAttributes(of element: AXUIElement) -> AttributeSet {
        AttributeSet(
            role: string(copy(element, kAXRoleAttribute)),
            subrole: string(copy(element, kAXSubroleAttribute)),
            title: string(copy(element, kAXTitleAttribute)),
            description: string(copy(element, kAXDescriptionAttribute)),
            value: nil,
            identifier: string(copy(element, kAXIdentifierAttribute)),
            frame: frame(copy(element, Self.frameAttribute)),
            childCount: nil
        )
    }

    private func attributes(of element: AXUIElement) -> AttributeSet {
        var childCount: CFIndex = 0
        AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &childCount)
        var read = AttributeSet(
            role: string(copy(element, kAXRoleAttribute)),
            subrole: string(copy(element, kAXSubroleAttribute)),
            title: string(copy(element, kAXTitleAttribute)),
            description: string(copy(element, kAXDescriptionAttribute)),
            value: value(copy(element, kAXValueAttribute)),
            identifier: string(copy(element, kAXIdentifierAttribute)),
            frame: frame(copy(element, Self.frameAttribute)),
            childCount: Int(childCount)
        )
        readDOM(of: element, into: &read)
        return read
    }

    private func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    private func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func string(_ value: CFTypeRef?) -> String? {
        guard let value, CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return (value as! CFString) as String
    }

    private func frame(_ value: CFTypeRef?) -> Frame? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var rect = CGRect.zero
        guard AXValueGetType(axValue) == .cgRect, AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return Frame(rect)
    }

    private func value(_ value: CFTypeRef?) -> ElementValue? {
        guard let value else { return nil }
        let typeID = CFGetTypeID(value)
        if typeID == CFStringGetTypeID() { return .string((value as! CFString) as String) }
        if typeID == CFBooleanGetTypeID() { return .bool(CFBooleanGetValue((value as! CFBoolean))) }
        if typeID == CFNumberGetTypeID() {
            var number = 0.0
            return CFNumberGetValue((value as! CFNumber), .doubleType, &number) ? .number(number) : nil
        }
        return nil
    }
}

/// The reader bound to the windows under one point, as the resolver's provider.
struct AppElementProvider: ElementProvider {
    let reader: AccessibilityReader
    let candidates: [Geometry.WindowRecord]
    let fallbackPID: pid_t

    func snapshot(at point: CGPoint) async -> ElementSnapshot? {
        await reader.snapshot(at: point, candidates: candidates, fallbackPID: fallbackPID)
    }
}
