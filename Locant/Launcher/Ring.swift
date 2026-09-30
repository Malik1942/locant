import AppKit

/// R27, PRD P1.11: four segments unfold from the ball on press-and-hold. Snap ↑, Text →, Color ↓,
/// Cut ←; release over a segment chooses, release at center cancels. Never opens on hover.
@MainActor
final class Ring {
    enum Segment: CaseIterable, Equatable {
        case snap, text, color, cut

        var symbol: String {
            switch self {
            case .snap: "camera.viewfinder"
            case .text: "text.viewfinder"
            case .color: "eyedropper"
            case .cut: "person.and.background.dotted"
            }
        }

        var title: String {
            switch self {
            case .snap: "Snap"
            case .text: "Text"
            case .color: "Color"
            case .cut: "Cut"
            }
        }

        /// Unit direction in AppKit coordinates (y up).
        var direction: CGPoint {
            switch self {
            case .snap: CGPoint(x: 0, y: 1)
            case .text: CGPoint(x: 1, y: 0)
            case .color: CGPoint(x: 0, y: -1)
            case .cut: CGPoint(x: -1, y: 0)
            }
        }

        var acceptsClipboardOnly: Bool { self == .snap || self == .cut }

        /// The name in `Preferences.hotkeyActions`.
        var actionName: String {
            switch self {
            case .snap: "snap"
            case .text: "text"
            case .color: "color"
            case .cut: "cut"
            }
        }
    }

    enum Tokens {
        static let outerRadius: CGFloat = 92
        /// The center is the disc as it looks under the cursor, so the ring reads as growing from it.
        static var innerRadius: CGFloat { FloatingBall.Tokens.diameter / 2 * FloatingBall.Tokens.hoverScale }
        /// v0.5 R39: AppKit's press default (`NSPressGestureRecognizer.minimumPressDuration`); a slower click stays a click.
        static let holdDelay: TimeInterval = 0.5
        static let labelDelay: TimeInterval = 0.2
        static let iconRadius: CGFloat = 54
    }

    private let panel: NSPanel
    private let view: RingView
    private var labelTask: Task<Void, Never>?
    private(set) var center = CGPoint.zero
    private(set) var hovered: Segment?
    /// R29: each segment's hotkey, shown beside its name.
    var hints: [Segment: String] = [:] {
        didSet { view.setHints(hints) }
    }

    init() {
        let side = Tokens.outerRadius * 2
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true // the same lift the disc has
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        view = RingView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        panel.contentView = view
    }

    /// `center` in AppKit screen points.
    func open(at center: CGPoint) {
        self.center = center
        hovered = nil
        let side = Tokens.outerRadius * 2
        panel.setFrameOrigin(CGPoint(x: center.x - side / 2, y: center.y - side / 2))
        panel.alphaValue = 0
        view.showLabels(false)
        view.highlight(nil)
        panel.orderFrontRegardless()
        view.unfold()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.reveal
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        labelTask?.cancel()
        labelTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Tokens.labelDelay))
            guard !Task.isCancelled else { return }
            self.view.showLabels(true)
        }
    }

    /// The segment under `point` (AppKit screen), updating the highlight.
    @discardableResult
    func hover(at point: CGPoint, commandHeld: Bool) -> Segment? {
        let segment = Self.segment(for: CGPoint(x: point.x - center.x, y: point.y - center.y), innerRadius: Tokens.innerRadius)
        hovered = segment
        view.highlight(segment)
        view.showCommandBadge(commandHeld)
        return segment
    }

    func close() {
        labelTask?.cancel()
        view.fold()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.dismiss
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(DesignTokens.dismiss * 1000) + 20))
            self.panel.orderOut(nil)
        }
    }

    /// Pure: which quadrant a delta from the center falls in; nil inside the center (cancel).
    nonisolated static func segment(for delta: CGPoint, innerRadius: CGFloat = 22) -> Segment? {
        guard hypot(delta.x, delta.y) > innerRadius else { return nil }
        if abs(delta.y) >= abs(delta.x) {
            return delta.y > 0 ? .snap : .color
        }
        return delta.x > 0 ? .text : .cut
    }
}

/// The disc's glass at ring size (the system's regular glass on macOS 26, `label.bg` before) with
/// four wedges, outline symbols, labels that fade in, and the filled hand at center. It unfolds
/// from the disc on the system spring and folds back on close. Unlike the disc, the ring carries
/// text, so it uses the regular glass, which tints itself against whatever is behind it: over a
/// white web page in Dark mode the clear glass left white symbols on white, an empty disc.
final class RingView: NSView {
    private let wedges = WedgeView()
    private var icons: [Ring.Segment: NSImageView] = [:]
    private var labels: [Ring.Segment: NSTextField] = [:]
    private var badges: [Ring.Segment: NSTextField] = [:]
    private let hand = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Everything drawn on the glass lives in one view: on macOS 26 it is the glass's content,
        // so the symbols and labels get the glass's legibility treatment; before, it sits over the material.
        let content = NSView(frame: bounds)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .regular
            glass.cornerRadius = frameRect.width / 2
            glass.contentView = content
            addSubview(glass)
        } else {
            let material = NSVisualEffectView(frame: bounds)
            material.material = .hudWindow
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = frameRect.width / 2
            material.layer?.masksToBounds = true
            addSubview(material)
            addSubview(content)
        }
        wedges.frame = bounds
        content.addSubview(wedges)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for segment in Ring.Segment.allCases {
            let icon = NSImageView()
            if let image = NSImage(systemSymbolName: segment.symbol, accessibilityDescription: segment.title) {
                image.isTemplate = true
                icon.image = image.withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
            }
            icon.contentTintColor = .labelColor
            let position = CGPoint(x: center.x + segment.direction.x * Ring.Tokens.iconRadius, y: center.y + segment.direction.y * Ring.Tokens.iconRadius)
            icon.frame = NSRect(x: position.x - 12, y: position.y - 6, width: 24, height: 24)
            content.addSubview(icon)
            icons[segment] = icon

            let label = NSTextField(labelWithString: segment.title)
            label.font = DesignTokens.sans
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.sizeToFit()
            label.frame.origin = CGPoint(x: position.x - label.frame.width / 2, y: position.y - 22)
            label.alphaValue = 0
            content.addSubview(label)
            labels[segment] = label

            if segment.acceptsClipboardOnly {
                let badge = NSTextField(labelWithString: "⌘") // v0.9 R78: ⌘ keeps it off disk; ⌥ is the ladder's
                badge.font = DesignTokens.sans
                badge.textColor = .secondaryLabelColor
                badge.sizeToFit()
                badge.frame.origin = CGPoint(x: icon.frame.maxX + 2, y: icon.frame.midY - badge.frame.height / 2)
                badge.alphaValue = 0
                content.addSubview(badge)
                badges[segment] = badge
            }
        }

        // The same hand, at the same size, as the disc shows when awake.
        hand.image = DiscView.handImage
        hand.imageScaling = .scaleProportionallyUpOrDown
        hand.contentTintColor = .labelColor
        let handSide = FloatingBall.Tokens.diameter - 2 * FloatingBall.Tokens.iconInset
        hand.frame = NSRect(x: center.x - handSide / 2, y: center.y - handSide / 2, width: handSide, height: handSide)
        content.addSubview(hand)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func highlight(_ segment: Ring.Segment?) {
        wedges.highlighted = segment
        wedges.needsDisplay = true
    }

    func showLabels(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.reveal
            for label in labels.values { label.animator().alphaValue = visible ? 1 : 0 }
        }
    }

    func showCommandBadge(_ visible: Bool) {
        for badge in badges.values { badge.alphaValue = visible ? 1 : 0 }
    }

    /// "Snap  ⌃⌥2": the hotkey after the name, smaller and quieter, the label kept centered.
    func setHints(_ hints: [Ring.Segment: String]) {
        for (segment, label) in labels {
            let text = NSMutableAttributedString(string: segment.title, attributes: [.font: DesignTokens.sans, .foregroundColor: NSColor.secondaryLabelColor])
            if let hint = hints[segment] {
                text.append(NSAttributedString(string: "  " + hint, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor]))
            }
            let midX = label.frame.midX
            label.attributedStringValue = text
            label.sizeToFit()
            label.frame.origin.x = midX - label.frame.width / 2
        }
    }

    // MARK: Motion

    /// Grows out of the disc: from the disc's size to full on the system spring.
    func unfold() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "fold")
        layer.transform = CATransform3DIdentity
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = centeredScale(FloatingBall.Tokens.diameter / bounds.width, in: bounds)
        spring.toValue = CATransform3DIdentity
        spring.mass = 1
        spring.stiffness = Spring.wake.stiffness
        spring.damping = Spring.wake.dampingCoefficient
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "unfold")
    }

    /// Settles back toward the disc while the panel fades.
    func fold() {
        guard let layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let ease = CABasicAnimation(keyPath: "transform")
        ease.fromValue = layer.presentation()?.transform ?? CATransform3DIdentity
        ease.toValue = centeredScale(0.85, in: bounds)
        ease.duration = DesignTokens.dismiss
        ease.timingFunction = CAMediaTimingFunction(name: .easeIn)
        ease.fillMode = .forwards
        ease.isRemovedOnCompletion = false
        layer.add(ease, forKey: "fold")
    }
}

/// The separators and the highlighted wedge.
final class WedgeView: NSView {
    var highlighted: Ring.Segment?

    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outer = bounds.width / 2
        let inner = Ring.Tokens.innerRadius
        if let highlighted {
            let base: CGFloat = switch highlighted {
            case .text: -45
            case .snap: 45
            case .cut: 135
            case .color: 225
            }
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: outer, startAngle: base, endAngle: base + 90)
            path.appendArc(withCenter: center, radius: inner, startAngle: base + 90, endAngle: base, clockwise: true)
            path.close()
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            path.fill()
        }
        NSColor.separatorColor.setStroke()
        let lines = NSBezierPath()
        lines.lineWidth = 1
        for angle in [45.0, 135.0, 225.0, 315.0] {
            let radians = angle * .pi / 180
            lines.move(to: CGPoint(x: center.x + cos(radians) * inner, y: center.y + sin(radians) * inner))
            lines.line(to: CGPoint(x: center.x + cos(radians) * outer, y: center.y + sin(radians) * outer))
        }
        lines.stroke()
        let disc = NSBezierPath(ovalIn: NSRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
        disc.lineWidth = 1
        disc.stroke()
    }
}
