import AppKit

/// PRD §6.2 tokens mapped to system constants. Nothing here is a value of our own.
@MainActor
enum DesignTokens {
    static var dim: NSColor { NSColor.black.withAlphaComponent(0.20) }
    static var highlightStroke: NSColor { .controlAccentColor }
    static var highlightFallback: NSColor { .secondaryLabelColor }
    static let strokeWidth: CGFloat = 2
    static let highlightRadius: CGFloat = 6
    static let labelRadius: CGFloat = 6
    static let spaceS: CGFloat = 4
    static let spaceM: CGFloat = 8
    static let spaceL: CGFloat = 12
    static let fieldMinWidth: CGFloat = 320
    static let reveal: TimeInterval = 0.200
    static let dismiss: TimeInterval = 0.120
    static let hover: TimeInterval = 0.080
    static let toastLife: TimeInterval = 1.000
    /// v0.5 R40: a one-line hint needs reading time.
    static let hintLife: TimeInterval = 6.000
    static var mono: NSFont { .monospacedSystemFont(ofSize: 11, weight: .regular) }
    static var sans: NSFont { .systemFont(ofSize: 12) }
    /// Labels flip above the element when its bottom is within this distance of the screen bottom.
    static let flipMargin: CGFloat = 40
    /// Frame handles: `highlight.stroke` on a white ring, as in Photos and Preview crop.
    static var handleRing: NSColor { .white }
}

/// What the hover label says about the element under the cursor: `role · identifier`, with the
/// identifier in mono and any caveat in the secondary color. Tells identifier quality before the click.
struct Readout: Equatable, Sendable {
    var role: String
    var identifier: String?
    var suffix: String?
    var isFallback: Bool

    static func describing(_ element: ResolvedElement?) -> Readout {
        guard let element else {
            return Readout(role: "no element info", identifier: nil, suffix: "image only", isFallback: true)
        }
        if element.role == ElementResolver.clusterRole {
            return Readout(role: "cluster", identifier: nil, suffix: "\(element.members?.count ?? 0) elements", isFallback: false)
        }
        // v0.8: a web node without an accessibility identifier shows its DOM handle instead.
        let handle = element.identifier ?? element.domReadout
        var role = element.role
        if handle == nil, let label = element.label {
            role += " \"\(label)\""
        }
        let suffix: String? = switch (handle, element.identifierSource) {
        case (nil, _): "no identifier"
        case (_, .possiblySymbolName): "may be a symbol name"
        default: nil
        }
        return Readout(role: role, identifier: handle, suffix: suffix, isFallback: false)
    }
}

/// Attributed strings for hud surfaces, built from the tokens.
@MainActor
enum HudText {
    static func readout(_ r: Readout) -> NSAttributedString {
        let s = NSMutableAttributedString(string: r.role, attributes: sansAttributes)
        if let identifier = r.identifier {
            s.append(NSAttributedString(string: " · ", attributes: sansAttributes))
            s.append(NSAttributedString(string: identifier, attributes: monoAttributes))
        }
        if let suffix = r.suffix {
            s.append(NSAttributedString(string: " · ", attributes: sansAttributes))
            s.append(NSAttributedString(string: suffix, attributes: secondaryAttributes))
        }
        return s
    }

    static func copied(identifier: String?) -> NSAttributedString {
        let s = NSMutableAttributedString(string: "Copied", attributes: sansAttributes)
        if let identifier {
            s.append(NSAttributedString(string: " · ", attributes: sansAttributes))
            s.append(NSAttributedString(string: identifier, attributes: monoAttributes))
        }
        return s
    }

    static func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: sansAttributes)
    }

    /// v0.8.1 R63: "→ Cursor · <window title>" beside the note field, the title secondary.
    static func pasteTarget(_ label: AgentPaste.TargetLabel) -> NSAttributedString {
        let s = NSMutableAttributedString(string: label.lead, attributes: sansAttributes)
        if let title = label.title {
            s.append(NSAttributedString(string: " · ", attributes: sansAttributes))
            s.append(NSAttributedString(string: title, attributes: secondaryAttributes))
        }
        return s
    }

    static var sansAttributes: [NSAttributedString.Key: Any] {
        [.font: DesignTokens.sans, .foregroundColor: NSColor.labelColor]
    }
    static var monoAttributes: [NSAttributedString.Key: Any] {
        [.font: DesignTokens.mono, .foregroundColor: NSColor.labelColor]
    }
    static var secondaryAttributes: [NSAttributedString.Key: Any] {
        [.font: DesignTokens.sans, .foregroundColor: NSColor.secondaryLabelColor]
    }
}

/// R2: one transparent, non-activating panel per screen over the live desktop. Reports hover and
/// click points in CG (accessibility) coordinates; draws highlight, label, and the note field.
/// R22: what the overlay is open for. Point is the default; the one-shot actions reuse the gesture.
enum OverlayMode: Equatable {
    case point, snap, text, cut

    var cursor: NSCursor {
        switch self {
        case .point, .text: .pointingHand
        case .snap, .cut: .crosshair
        }
    }
}

@MainActor
final class SelectionOverlay {
    var mode: OverlayMode = .point
    /// Settings "Adjust selection before capturing": a drawn frame waits with handles until Return.
    /// Point ignores it; its frame already pauses at the note field.
    var adjustsRegion = false
    var onHover: ((CGPoint) -> Void)?
    /// A click, and whether Shift was held (v0.8 R58: Shift adds the element to a set).
    var onClick: ((CGPoint, Bool) -> Void)?
    /// Shift pressed while hovering, for the one-time hint.
    var onShiftPressed: (() -> Void)?
    /// Return while hovering. Returns true when it was taken (v0.8 R58: it confirms a set as it
    /// stands); otherwise Return is a click at the cursor.
    var onReturn: (() -> Bool)?
    var onCancel: (() -> Void)?
    var onCommit: ((String) -> Void)?
    /// Option pressed while hovering: step the selection to the parent.
    var onOptionPressed: (() -> Void)?
    /// A drawn frame (CG points) and the drag's start point, for the window hit-test.
    var onRegion: ((CGRect, CGPoint) -> Void)?

    private var panels: [OverlayPanel] = []
    private var dismissing: [OverlayPanel] = []
    private(set) var primaryHeight: CGFloat = 0
    private var cursorPushed = false

    var isShowing: Bool { !panels.isEmpty }

    func show() {
        guard panels.isEmpty else { return }
        primaryHeight = Self.currentPrimaryHeight()
        panels = NSScreen.screens.map { screen in
            let panel = OverlayPanel(screen: screen)
            panel.contentOverlay.owner = self
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            return panel
        }
        panels.first?.makeKey()
        panels.first?.makeFirstResponder(panels.first?.contentOverlay)
        mode.cursor.push()
        cursorPushed = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.reveal
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for panel in panels { panel.animator().alphaValue = 1 }
        }
    }

    func dismiss() {
        guard !panels.isEmpty else { return }
        dismissing = panels
        panels = []
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.dismiss
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for panel in dismissing { panel.animator().alphaValue = 0 }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(DesignTokens.dismiss * 1000) + 20))
            for panel in self.dismissing { panel.orderOut(nil) }
            self.dismissing = []
        }
    }

    /// Highlights `frame` (CG points). A nil frame shows the fallback square around `point`.
    /// v0.8.1 R59: true when an outline was drawn.
    @discardableResult
    func setHighlight(_ frame: CGRect?, readout: Readout, around point: CGPoint) -> Bool {
        let rect = Geometry.appKitRect(fromCG: frame ?? Self.fallbackRect(around: point), primaryHeight: primaryHeight)
        let target = panel(containing: rect)
        var drawn = false
        for panel in panels {
            if panel === target {
                drawn = panel.contentOverlay.showHighlight(screenRect: rect, readout: readout)
            } else {
                panel.contentOverlay.hideHighlight()
            }
        }
        return drawn
    }

    /// R6: the note field anchored to the element's bottom edge. The highlight stays.
    func showNoteField(anchoredTo frame: CGRect?, around point: CGPoint) {
        let rect = Geometry.appKitRect(fromCG: frame ?? Self.fallbackRect(around: point), primaryHeight: primaryHeight)
        guard let target = panel(containing: rect) else { return }
        for panel in panels { panel.contentOverlay.lock() }
        target.makeKey()
        target.contentOverlay.showNoteField(screenRect: rect)
    }

    /// v0.8.1 R63: where Return will paste, beside the note field; nil hides it.
    func setNoteTarget(_ text: NSAttributedString?) {
        panels.first { $0.contentOverlay.hasNoteField }?.contentOverlay.setNoteTarget(text)
    }

    // MARK: Called by the content views (AppKit screen coordinates)

    func hover(atAppKit point: CGPoint) {
        onHover?(Geometry.cgPoint(fromAppKit: point, primaryHeight: primaryHeight))
    }

    func click(atAppKit point: CGPoint, shift: Bool) {
        onClick?(Geometry.cgPoint(fromAppKit: point, primaryHeight: primaryHeight), shift)
    }

    /// v0.5 R38: Return is a click at the cursor, unless the owner takes it first.
    func returnPressed(shift: Bool) {
        if onReturn?() == true { return }
        click(atAppKit: NSEvent.mouseLocation, shift: shift)
    }

    /// v0.8 R58: the elements already in the set (CG rects), each outlined and numbered on its display.
    func setPinned(_ frames: [CGRect]) {
        let rects = frames.map { Geometry.appKitRect(fromCG: $0, primaryHeight: primaryHeight) }
        for panel in panels { panel.contentOverlay.showPinned(rects) }
    }

    func region(atAppKit rect: CGRect, start: CGPoint) {
        onRegion?(Geometry.cgRect(fromAppKit: rect, primaryHeight: primaryHeight),
                  Geometry.cgPoint(fromAppKit: start, primaryHeight: primaryHeight))
    }

    /// R12: 1 pt marks on every element kept inside the drawn frame (CG rects).
    func showMarks(_ frames: [CGRect]) {
        let rects = frames.map { Geometry.appKitRect(fromCG: $0, primaryHeight: primaryHeight) }
        for panel in panels { panel.contentOverlay.showMarks(rects) }
    }

    // MARK: Screen helpers

    static func currentPrimaryHeight() -> CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// CG-space frame of the display containing `point`.
    static func displayFrameCG(containing point: CGPoint) -> CGRect {
        let primaryHeight = currentPrimaryHeight()
        let frames = NSScreen.screens.map { Geometry.cgRect(fromAppKit: $0.frame, primaryHeight: primaryHeight) }
        return frames.first { $0.contains(point) } ?? frames.first ?? .zero
    }

    static func fallbackRect(around point: CGPoint) -> CGRect {
        let side = Geometry.fallbackCropSide
        return CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
    }

    private func panel(containing rect: CGRect) -> OverlayPanel? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return panels.first { $0.frame.contains(center) } ?? panels.first
    }
}

// MARK: - Panel

final class OverlayPanel: NSPanel {
    let contentOverlay: OverlayContentView

    init(screen: NSScreen) {
        contentOverlay = OverlayContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = DesignTokens.dim
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        contentView = contentOverlay
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Content view

final class OverlayContentView: NSView, NSTextFieldDelegate {
    weak var owner: SelectionOverlay?
    /// When set, this view serves the color picker instead of the selection overlay (R25).
    weak var picker: ColorPickerSession?

    private let highlight = HighlightView()
    private let label = HudLabel()
    private var noteField: NoteFieldView?
    /// v0.8.1 R63: where Return will paste, and the element the field is anchored to (local coordinates).
    private let targetLabel = HudLabel()
    private var noteAnchor: CGRect = .zero
    private var trackingArea: NSTrackingArea?
    private var locked = false

    // R11 region gesture
    private static let dragThreshold: CGFloat = 6
    private var dragStart: CGPoint?
    private var isDragging = false
    private let marquee = RegionFrameView()
    private let sizeLabel = HudLabel()
    private var marks: [HighlightView] = []

    // Adjustable frame: handles resize, the body moves, arrows nudge, Return captures, a drag
    // outside draws a new one. Hover stays off while it is up.
    private var editRegion: CGRect?
    private var editHit: RegionEditor.Hit = .outside
    private var editStart: CGPoint = .zero
    private var editBase: CGRect = .zero
    var isAdjusting: Bool { editRegion != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        highlight.isHidden = true
        label.isHidden = true
        addSubview(highlight)
        addSubview(label)
        marquee.isHidden = true
        sizeLabel.isHidden = true
        addSubview(marquee)
        addSubview(sizeLabel)
        targetLabel.isHidden = true
        addSubview(targetLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    /// v0.5 R37: a click on a panel that is not key is still a click. Only the first display's panel
    /// is made key; without this every other display dropped the first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: owner?.mode.cursor ?? .pointingHand)
    }

    override func mouseMoved(with event: NSEvent) {
        if let picker { picker.cursorMoved(NSEvent.mouseLocation); return }
        guard !locked, let window else { return }
        if let region = editRegion {
            Self.cursor(for: RegionEditor.hit(event.locationInWindow, in: region), outside: owner?.mode.cursor ?? .crosshair).set()
            return
        }
        owner?.hover(atAppKit: window.convertPoint(toScreen: event.locationInWindow))
    }

    override func mouseDown(with event: NSEvent) {
        if let picker { picker.clicked(); return }
        guard !locked else { return }
        let point = event.locationInWindow
        if let region = editRegion {
            editHit = RegionEditor.hit(point, in: region)
            editStart = point
            editBase = region
            if event.clickCount == 2, editHit == .inside { confirmRegion(); return }
            guard editHit == .outside else { return }
        }
        dragStart = point
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !locked else { return }
        let point = event.locationInWindow
        if editRegion != nil, editHit != .outside {
            let delta = CGPoint(x: point.x - editStart.x, y: point.y - editStart.y)
            let moved: CGRect
            switch editHit {
            case .handle(let handle): moved = RegionEditor.resize(editBase, handle: handle, by: delta)
            case .inside: moved = RegionEditor.move(editBase, by: delta, within: bounds)
            case .outside: moved = editBase
            }
            let clamped = moved.intersection(bounds)
            editRegion = clamped
            setRegion(clamped)
            return
        }
        guard let start = dragStart else { return }
        if !isDragging {
            guard hypot(point.x - start.x, point.y - start.y) > Self.dragThreshold else { return }
            isDragging = true
            highlight.isHidden = true
            label.isHidden = true
            marquee.showsHandles = false
            marquee.isHidden = false
            sizeLabel.isHidden = false
        }
        setRegion(Self.normalized(start, point))
    }

    override func mouseUp(with event: NSEvent) {
        guard !locked, let window, let start = dragStart else { return }
        dragStart = nil
        if isDragging {
            isDragging = false
            let rect = Self.normalized(start, event.locationInWindow)
            guard rect.width >= 2, rect.height >= 2 else {
                if let region = editRegion { beginAdjusting(region) } else { marquee.isHidden = true; sizeLabel.isHidden = true }
                return
            }
            if owner?.adjustsRegion == true, owner?.mode != .point {
                beginAdjusting(rect)
            } else {
                sizeLabel.isHidden = true
                owner?.region(atAppKit: window.convertToScreen(convert(rect, to: nil)), start: window.convertPoint(toScreen: start))
            }
        } else if editRegion == nil {
            owner?.click(atAppKit: window.convertPoint(toScreen: event.locationInWindow), shift: event.modifierFlags.contains(.shift))
        }
    }

    /// The marquee and its size label follow `rect` (local coordinates).
    private func setRegion(_ rect: CGRect) {
        marquee.region = rect
        var text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded())) pt"
        if marquee.showsHandles { text += " · ↩ capture · esc cancel" }
        sizeLabel.set(HudText.plain(text))
        sizeLabel.frame = anchoredFrame(size: sizeLabel.hudSize, below: rect)
    }

    private func beginAdjusting(_ rect: CGRect) {
        editRegion = rect
        editHit = .outside
        marquee.showsHandles = true
        marquee.isHidden = false
        sizeLabel.isHidden = false
        setRegion(rect)
    }

    private func confirmRegion() {
        guard let window, let region = editRegion else { return }
        editRegion = nil
        sizeLabel.isHidden = true
        let center = CGPoint(x: region.midX, y: region.midY)
        owner?.region(atAppKit: window.convertToScreen(convert(region, to: nil)), start: window.convertPoint(toScreen: center))
    }

    private func nudge(by delta: CGPoint) {
        guard let region = editRegion else { return }
        let moved = RegionEditor.move(region, by: delta, within: bounds)
        editRegion = moved
        setRegion(moved)
    }

    private static func cursor(for hit: RegionEditor.Hit, outside: NSCursor) -> NSCursor {
        switch hit {
        case .inside: return .openHand
        case .outside: return outside
        case .handle(let handle):
            let position: NSCursor.FrameResizePosition
            switch handle {
            case .topLeft: position = .topLeft
            case .top: position = .top
            case .topRight: position = .topRight
            case .right: position = .right
            case .bottomRight: position = .bottomRight
            case .bottom: position = .bottom
            case .bottomLeft: position = .bottomLeft
            case .left: position = .left
            }
            return .frameResize(position: position, directions: .all)
        }
    }

    private static func normalized(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    func showMarks(_ screenRects: [CGRect]) {
        guard let window else { return }
        marks.forEach { $0.removeFromSuperview() }
        marks = screenRects.map { rect in
            let mark = HighlightView()
            mark.isFallback = true
            mark.strokeWidth = 1
            mark.cornerRadius = 3
            mark.frame = convert(window.convertFromScreen(rect), from: nil)
            addSubview(mark)
            return mark
        }
    }

    override func keyDown(with event: NSEvent) {
        if let picker {
            switch event.keyCode {
            case 53: picker.cancelled()
            case 36, 76: picker.clicked() // v0.5 R38: Return copies, like the click
            case 123: picker.nudgeBy(dx: -1, dy: 0)
            case 124: picker.nudgeBy(dx: 1, dy: 0)
            case 125: picker.nudgeBy(dx: 0, dy: 1)
            case 126: picker.nudgeBy(dx: 0, dy: -1)
            default: break
            }
            return
        }
        if event.keyCode == 53 { // Esc
            owner?.onCancel?()
            return
        }
        guard editRegion != nil else {
            // v0.5 R38: Return is a click at the cursor; the hover is the selection.
            if event.keyCode == 36 || event.keyCode == 76, !locked {
                owner?.returnPressed(shift: event.modifierFlags.contains(.shift))
            }
            return
        }
        switch event.keyCode {
        case 36, 76: // Return, keypad Enter
            confirmRegion()
        case 123, 124, 125, 126:
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case 123: nudge(by: CGPoint(x: -step, y: 0))
            case 124: nudge(by: CGPoint(x: step, y: 0))
            case 125: nudge(by: CGPoint(x: 0, y: -step))
            default: nudge(by: CGPoint(x: 0, y: step))
            }
        default:
            break
        }
    }

    private var optionWasDown = false
    private var shiftWasDown = false

    override func flagsChanged(with event: NSEvent) {
        let optionDown = event.modifierFlags.contains(.option)
        let shiftDown = event.modifierFlags.contains(.shift)
        defer { optionWasDown = optionDown; shiftWasDown = shiftDown }
        if optionDown, !optionWasDown, !locked {
            owner?.onOptionPressed?()
        }
        if shiftDown, !shiftWasDown, !locked {
            owner?.onShiftPressed?()
        }
    }

    // v0.8 R58: the set so far, each outlined like the hover and numbered at its top-left corner.
    private var pinned: [NSView] = []

    func showPinned(_ screenRects: [CGRect]) {
        guard let window else { return }
        pinned.forEach { $0.removeFromSuperview() }
        pinned = []
        for (index, rect) in screenRects.enumerated() {
            let local = convert(window.convertFromScreen(rect), from: nil)
            guard bounds.intersects(local) else { continue }
            let outline = HighlightView()
            outline.frame = local
            addSubview(outline, positioned: .below, relativeTo: highlight)
            let badge = HudLabel()
            badge.set(NSAttributedString(string: "\(index + 1)", attributes: HudText.monoAttributes))
            var origin = CGPoint(x: local.minX, y: local.maxY + DesignTokens.spaceS)
            origin.x = min(max(origin.x, DesignTokens.spaceS), bounds.width - badge.hudSize.width - DesignTokens.spaceS)
            origin.y = min(origin.y, bounds.height - badge.hudSize.height - DesignTokens.spaceS)
            badge.frame = CGRect(origin: origin, size: badge.hudSize)
            addSubview(badge)
            pinned.append(contentsOf: [outline, badge])
        }
    }

    func lock() { locked = true }

    /// v0.8.1 R59: false when nothing was drawn (a frame is being dragged or adjusted), so no tap marks it.
    @discardableResult
    func showHighlight(screenRect: CGRect, readout: Readout) -> Bool {
        guard let window, !isDragging, !isAdjusting else { return false }
        let local = convert(window.convertFromScreen(screenRect), from: nil)
        highlight.isFallback = readout.isFallback
        label.set(HudText.readout(readout))
        let labelFrame = anchoredFrame(size: label.hudSize, below: local)

        let wasHidden = highlight.isHidden
        highlight.isHidden = false
        label.isHidden = noteField != nil
        if wasHidden {
            highlight.frame = local
            label.frame = labelFrame
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DesignTokens.hover
                highlight.animator().frame = local
                label.animator().frame = labelFrame
            }
        }
        highlight.needsDisplay = true
        return true
    }

    func hideHighlight() {
        highlight.isHidden = true
        label.isHidden = true
    }

    func showNoteField(screenRect: CGRect) {
        guard let window, noteField == nil else { return }
        locked = true
        label.isHidden = true
        sizeLabel.isHidden = true
        let local = convert(window.convertFromScreen(screenRect), from: nil)
        noteAnchor = local
        let size = CGSize(width: max(local.width, DesignTokens.fieldMinWidth), height: NoteFieldView.height)
        let field = NoteFieldView(frame: anchoredFrame(size: size, below: local))
        field.textField.delegate = self
        field.alphaValue = 0
        addSubview(field)
        noteField = field
        window.makeFirstResponder(field.textField)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.reveal
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            field.animator().alphaValue = 1
        }
    }

    var hasNoteField: Bool { noteField != nil }

    /// v0.8.1 R63: where Return will paste, on the far side of the note field from the element and
    /// left-aligned with it; kept on screen. Nil hides it.
    func setNoteTarget(_ text: NSAttributedString?) {
        guard let field = noteField, let text else {
            targetLabel.isHidden = true
            return
        }
        targetLabel.set(text)
        let size = targetLabel.hudSize
        var origin = CGPoint(x: field.frame.minX, y: field.frame.minY - DesignTokens.spaceS - size.height)
        if field.frame.midY > noteAnchor.midY { // the field flipped above the element
            origin.y = field.frame.maxY + DesignTokens.spaceS
        }
        origin.x = min(max(origin.x, DesignTokens.spaceM), bounds.width - size.width - DesignTokens.spaceM)
        origin.y = min(max(origin.y, DesignTokens.spaceM), bounds.height - size.height - DesignTokens.spaceM)
        targetLabel.frame = CGRect(origin: origin, size: size)
        targetLabel.isHidden = false
    }

    /// 8 pt below the element, or above it when within 40 pt of the screen bottom; kept on screen.
    private func anchoredFrame(size: CGSize, below rect: CGRect) -> CGRect {
        var origin = CGPoint(x: rect.minX, y: rect.minY - DesignTokens.spaceM - size.height)
        if rect.minY < DesignTokens.flipMargin {
            origin.y = rect.maxY + DesignTokens.spaceM
        }
        origin.x = min(max(origin.x, DesignTokens.spaceM), bounds.width - size.width - DesignTokens.spaceM)
        origin.y = min(max(origin.y, DesignTokens.spaceM), bounds.height - size.height - DesignTokens.spaceM)
        return CGRect(origin: origin, size: size)
    }

    // MARK: NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            owner?.onCommit?(noteField?.textField.stringValue ?? "")
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            owner?.onCancel?()
            return true
        }
        return false
    }
}

// MARK: - Highlight

/// `highlight.stroke` at `highlight.radius`, no fill; dashed `highlight.fallback` for the no-element state.
final class HighlightView: NSView {
    var isFallback = false { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = DesignTokens.highlightRadius
    var strokeWidth: CGFloat = DesignTokens.strokeWidth

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Chrome never takes the mouse: the content view owns the gesture. (A view that receives the
    /// mouse-down and is then hidden stops getting the drag, which is how region select broke.)
    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }   // AX hit tests reach this off the main thread

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = strokeWidth
        if isFallback {
            path.setLineDash([6, 4], count: 2, phase: 0)
            DesignTokens.highlightFallback.setStroke()
        } else {
            DesignTokens.highlightStroke.setStroke()
        }
        path.stroke()
    }
}

// MARK: - Region frame

/// The drawn frame: `highlight.stroke`, square corners; eight handles while the frame is adjustable.
/// `region` is in the superview's coordinates; the view is outset so the handles are not clipped.
final class RegionFrameView: NSView {
    static var pad: CGFloat { RegionEditor.handleSize / 2 + 1 }

    var showsHandles = false { didSet { needsDisplay = true } }
    var region: CGRect = .zero {
        didSet {
            frame = region.insetBy(dx: -Self.pad, dy: -Self.pad)
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }   // AX hit tests reach this off the main thread

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: Self.pad, dy: Self.pad)
        let stroke = DesignTokens.strokeWidth
        let path = NSBezierPath(rect: rect.insetBy(dx: stroke / 2, dy: stroke / 2))
        path.lineWidth = stroke
        DesignTokens.highlightStroke.setStroke()
        path.stroke()
        guard showsHandles else { return }
        let size = RegionEditor.handleSize
        for handle in RegionEditor.Handle.allCases {
            let center = RegionEditor.center(of: handle, in: rect)
            let dot = NSBezierPath(ovalIn: NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size))
            DesignTokens.handleRing.setFill()
            dot.fill()
            dot.lineWidth = 1.5
            DesignTokens.highlightStroke.setStroke()
            dot.stroke()
        }
    }
}

// MARK: - Hud label

/// `label.bg`: hud material with a 6 pt radius, `space.m` / `space.s` padding.
final class HudLabel: NSVisualEffectView {
    private let text = NSTextField(labelWithString: "")
    private let maxTextWidth: CGFloat = 480

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = DesignTokens.labelRadius
        layer?.masksToBounds = true
        text.maximumNumberOfLines = 1
        text.lineBreakMode = .byTruncatingMiddle
        addSubview(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }   // AX hit tests reach this off the main thread

    func set(_ string: NSAttributedString) {
        text.attributedStringValue = string
        text.sizeToFit()
        if text.frame.width > maxTextWidth {
            text.frame.size.width = maxTextWidth
        }
        text.frame.origin = CGPoint(x: DesignTokens.spaceM, y: DesignTokens.spaceS)
    }

    var hudSize: CGSize {
        CGSize(width: text.frame.width + 2 * DesignTokens.spaceM, height: text.frame.height + 2 * DesignTokens.spaceS)
    }

    /// Pill shape for toasts.
    func makePill() {
        layer?.cornerRadius = hudSize.height / 2
    }
}

// MARK: - Note field

/// PRD note-field spec: `field.width`, `label.bg`, `label.sans`, placeholder "What should change?",
/// right-aligned hint in the secondary color.
final class NoteFieldView: NSVisualEffectView {
    static let height: CGFloat = 28
    let textField = NSTextField()
    private let hint = NSTextField(labelWithString: "↩ copy · esc cancel")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = DesignTokens.labelRadius
        layer?.masksToBounds = true

        hint.font = DesignTokens.sans
        hint.textColor = .secondaryLabelColor
        hint.sizeToFit()
        hint.frame.origin = CGPoint(
            x: frameRect.width - hint.frame.width - DesignTokens.spaceM,
            y: (frameRect.height - hint.frame.height) / 2
        )
        addSubview(hint)

        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = DesignTokens.sans
        textField.textColor = .labelColor
        textField.placeholderString = "What should change?"
        textField.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        let fieldHeight: CGFloat = 17
        textField.frame = CGRect(
            x: DesignTokens.spaceM,
            y: (frameRect.height - fieldHeight) / 2,
            width: hint.frame.minX - DesignTokens.spaceM * 2,
            height: fieldHeight
        )
        addSubview(textField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - Toast

/// PRD toast spec: a pill on `label.bg` near where the element was, `toast.life`, then `motion.dismiss`.
/// v0.5 R40: the same pill carries the hints, at the bottom center of a display for `hint.life`.
@MainActor
final class Toast {
    private var panel: NSPanel?
    private var generation = 0

    /// `anchor` is in CG points; the pill sits just below it (above when near the screen bottom).
    func show(_ text: NSAttributedString, near anchor: CGRect, life: TimeInterval = DesignTokens.toastLife) {
        let label = makeLabel(text)
        let size = label.hudSize
        let primaryHeight = SelectionOverlay.currentPrimaryHeight()
        let rect = Geometry.appKitRect(fromCG: anchor, primaryHeight: primaryHeight)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? rect
        var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY - DesignTokens.spaceM - size.height)
        if origin.y < bounds.minY + DesignTokens.flipMargin {
            origin.y = rect.maxY + DesignTokens.spaceM
        }
        present(label, at: clamp(origin, size: size, in: bounds), life: life)
    }

    /// The bottom center of the display holding `point` (AppKit screen points): the ⌘⇧5 toolbar's
    /// spot, clear of the hover label wherever the cursor is.
    func show(_ text: NSAttributedString, atBottomOf point: CGPoint, life: TimeInterval) {
        let label = makeLabel(text)
        let size = label.hudSize
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? .zero
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.minY + DesignTokens.flipMargin)
        present(label, at: clamp(origin, size: size, in: bounds), life: life)
    }

    /// Takes the pill down early, with `motion.dismiss`.
    func hide() {
        guard let panel else { return }
        generation += 1
        self.panel = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.dismiss
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(DesignTokens.dismiss * 1000) + 20))
            panel.orderOut(nil)
        }
    }

    private func makeLabel(_ text: NSAttributedString) -> HudLabel {
        let label = HudLabel()
        label.set(text)
        label.frame = CGRect(origin: .zero, size: label.hudSize)
        label.makePill()
        return label
    }

    private func clamp(_ origin: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, bounds.minX + DesignTokens.spaceM), bounds.maxX - size.width - DesignTokens.spaceM),
            y: min(max(origin.y, bounds.minY + DesignTokens.spaceM), bounds.maxY - size.height - DesignTokens.spaceM)
        )
    }

    private func present(_ label: HudLabel, at origin: CGPoint, life: TimeInterval) {
        panel?.orderOut(nil)
        generation += 1
        let current = generation
        let size = label.hudSize

        let toastPanel = NSPanel(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toastPanel.level = .screenSaver
        toastPanel.isOpaque = false
        toastPanel.backgroundColor = .clear
        toastPanel.hasShadow = false
        toastPanel.ignoresMouseEvents = true
        toastPanel.hidesOnDeactivate = false
        toastPanel.isReleasedWhenClosed = false
        toastPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        toastPanel.contentView = label
        toastPanel.alphaValue = 0
        toastPanel.orderFrontRegardless()
        panel = toastPanel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.reveal
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            toastPanel.animator().alphaValue = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(life))
            guard self.generation == current, let panel = self.panel else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = DesignTokens.dismiss
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }
            guard self.generation == current else { return }
            self.panel?.orderOut(nil)
            self.panel = nil
        }
    }
}
