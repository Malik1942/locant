import AppKit
import QuartzCore

/// v0.3 R20, PRD P1.11: the quiet second entry point. A 48 pt glass disc that rests translucent,
/// tucks into the nearest free stretch of a screen edge (left, right, or the bottom beside the
/// Dock; specs/ball-edges.md), which becomes its home, wakes there as the cursor approaches (moving
/// in far enough for the ring to open on screen), and starts Point on click. Excluded from
/// captures through the own-windows filter.
@MainActor
final class FloatingBall {
    enum State: Equatable { case rest, docked, awake, ready }

    enum Tokens {
        static let diameter: CGFloat = 48
        /// Clear room around the disc inside its window, for the hover swell and the shadow.
        static let pad: CGFloat = 10
        static var panelSide: CGFloat { diameter + 2 * pad }
        static let approach: CGFloat = 80
        static let dockDelay: TimeInterval = 2
        static let firstLaunchInset: CGFloat = 24
        static let restAlpha: CGFloat = 0.9
        static let dockedAlpha: CGFloat = 0.9
        /// How much of the disc stays on screen when tucked into an edge: enough to find it.
        static let dockedVisible: CGFloat = 0.6
        /// A drop with the center this close to an edge tucks in at once, without the idle wait.
        static let edgeSnap: CGFloat = diameter
        /// Awake near an edge, the disc moves in so the ring (outer radius 92) stays on screen.
        static let ringMargin: CGFloat = Ring.Tokens.outerRadius + 8
        /// `ball.glow`: a faint light at the center whose strength drifts over `glowPeriod`.
        static let glowAlpha: CGFloat = 0.14
        static let glowLow: Float = 0.35
        static let glowHigh: Float = 1.0
        static let glowPeriod: TimeInterval = 6
        static let hoverScale: CGFloat = 1.04
        static let dockedScale: CGFloat = 1
        /// Only when coming out of an edge does the disc swell from below size.
        static let wakeFromScale: CGFloat = 0.94
        static let iconInset: CGFloat = 13
        static let firstLaunchReveal: TimeInterval = 0.8
        /// After an app launches or quits, the Dock is read again once it has grown or shrunk.
        static let dockSettle: Duration = .milliseconds(600)
    }

    /// Click: start Point.
    var onPoint: (() -> Void)?
    /// The ball's home moved (a drag, a throw, a tuck); persist it (AppKit screen points, window origin).
    var onMoved: ((CGPoint) -> Void)?
    /// A ring segment was chosen; `clipboardOnly` when ⌘ was held (v0.9 R78; ⌥ until 0.8.1).
    var onAction: ((Ring.Segment, Bool) -> Void)?
    /// v0.8.1 R59: taps as the ring opens and as the pointer crosses into another segment.
    var feedback: Feedback?
    /// R29: each segment's hotkey, shown beside its name on the ring.
    var ringHints: [Ring.Segment: String] = [:] {
        didSet { ring.hints = ringHints }
    }
    /// Settings "Auto-hide": idle, the disc tucks into the nearest edge. Off, it stays where it is.
    var autoHide = true {
        didSet {
            guard autoHide != oldValue else { return }
            if autoHide {
                scheduleDock()
            } else {
                dockTask?.cancel()
                if state == .docked { set(.rest) }
            }
        }
    }

    private let ring = Ring()
    private let ghost = BallGhost()
    private let reader: AccessibilityReader
    private var holdTask: Task<Void, Never>?
    private(set) var ringOpen = false

    private let panel: NSPanel
    private let view: BallView
    private let glide: Glide
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private(set) var state: State = .rest
    /// Home: where the ball rests and wakes from. A tuck moves it to the tucked spot (R82).
    private var freeOrigin: CGPoint
    /// Where the window was last sent (awake near an edge it sits inward of `freeOrigin`).
    private var shownOrigin: CGPoint
    /// The spot the ball is tucked into while docked.
    private var tucked: BallEdges.Tuck?
    /// R81: the Dock's tiles in AppKit coordinates, as last read; nil when unknown.
    private var dockFrame: CGRect?
    private var dockRead: Task<Void, Never>?
    private var dockTask: Task<Void, Never>?
    /// After a drop docks the disc, the cursor is still on it; stay docked until it has left.
    private var holdDock = false
    /// The saved origin was off every connected display and had to be pulled onto one.
    private let restoredOffScreen: Bool

    init(origin: CGPoint?, reader: AccessibilityReader) {
        let size = NSSize(width: Tokens.panelSide, height: Tokens.panelSide)
        let start = origin.map { Self.onScreenOrigin($0, screens: Self.screenFrames, visible: Self.visibleFrames) } ?? Self.firstLaunchOrigin()
        self.reader = reader
        restoredOffScreen = origin != nil && start != origin
        freeOrigin = start
        shownOrigin = start
        panel = NSPanel(contentRect: NSRect(origin: start, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true // the soft lift the system gives glass
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        view = BallView(frame: NSRect(origin: .zero, size: size))
        glide = Glide(window: panel)
        panel.contentView = view
        view.ball = self
    }

    private static var screenFrames: [CGRect] { NSScreen.screens.map(\.frame) }
    private static var visibleFrames: [CGRect] { NSScreen.screens.map(\.visibleFrame) }

    private static var centerOffset: CGFloat { Tokens.pad + Tokens.diameter / 2 }

    private static func origin(forCenter center: CGPoint) -> CGPoint {
        CGPoint(x: center.x - centerOffset, y: center.y - centerOffset)
    }

    private static func center(forOrigin origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + centerOffset, y: origin.y + centerOffset)
    }

    /// A saved origin is trusted only while the disc's center falls on a connected display: after
    /// a display goes away the disc would otherwise sit where nothing shows it. A tuck or a home on
    /// the bottom edge beside the Dock lies below `visibleFrame` but on the screen, so it passes.
    /// Off every screen, the whole disc is brought inside the visible frame it lies nearest
    /// (`visible`, which defaults to `screens`).
    static func onScreenOrigin(_ origin: CGPoint, screens: [CGRect], visible: [CGRect]? = nil) -> CGPoint {
        let targets = visible ?? screens
        guard !screens.isEmpty, !targets.isEmpty else { return origin }
        let offset = Tokens.pad + Tokens.diameter / 2
        let center = CGPoint(x: origin.x + offset, y: origin.y + offset)
        if screens.contains(where: { $0.contains(center) }) { return origin }
        func distance(to frame: CGRect) -> CGFloat {
            hypot(max(frame.minX - center.x, 0, center.x - frame.maxX), max(frame.minY - center.y, 0, center.y - frame.maxY))
        }
        guard let nearest = targets.min(by: { distance(to: $0) < distance(to: $1) }) else { return origin }
        let radius = Tokens.diameter / 2
        let safe = CGPoint(
            x: min(max(center.x, nearest.minX + radius), nearest.maxX - radius),
            y: min(max(center.y, nearest.minY + radius), nearest.maxY - radius)
        )
        return CGPoint(x: safe.x - offset, y: safe.y - offset)
    }

    static func firstLaunchOrigin() -> CGPoint {
        let frame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        return CGPoint(
            x: frame.maxX - Tokens.firstLaunchInset - Tokens.diameter - Tokens.pad,
            y: frame.minY + Tokens.firstLaunchInset - Tokens.pad
        )
    }

    func show(firstLaunch: Bool) {
        if restoredOffScreen { onMoved?(freeOrigin) }
        panel.alphaValue = 0
        view.apply(.rest, animated: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = firstLaunch ? Tokens.firstLaunchReveal : DesignTokens.reveal
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = Tokens.restAlpha
        }
        refreshDock()
        startMonitors()
        scheduleDock()
    }

    func hide() {
        stopMonitors()
        ghost.hide()
        glide.cancel()
        dockTask?.cancel()
        dockTask = nil
        dockRead?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.dismiss
            panel.animator().alphaValue = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(DesignTokens.dismiss * 1000) + 20))
            self.panel.orderOut(nil)
        }
    }

    // MARK: Proximity

    private func startMonitors() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.cursorMoved(to: point) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.cursorMoved(to: point) }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDock(after: Tokens.dockSettle) }
            }
        }
    }

    private func stopMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers = []
        globalMonitor = nil
        localMonitor = nil
        screenObserver = nil
    }

    /// A display came or went. A disc left where nothing shows it comes back onto the nearest
    /// display, and the new spot is saved so the next launch starts there too.
    private func screensChanged() {
        refreshDock()
        guard !view.isDragging, !ringOpen else { return }
        let safe = Self.onScreenOrigin(freeOrigin, screens: Self.screenFrames, visible: Self.visibleFrames)
        let shownOnScreen = Self.screenFrames.contains { $0.contains(discCenter) }
        guard safe != freeOrigin || !shownOnScreen else { return }
        glide.cancel()
        dockTask?.cancel()
        holdDock = false
        freeOrigin = safe
        shownOrigin = safe
        panel.setFrameOrigin(safe)
        onMoved?(safe)
        if state == .docked { set(.rest) } else { scheduleDock() }
    }

    private var discCenter: CGPoint { CGPoint(x: panel.frame.midX, y: panel.frame.midY) }

    private func cursorMoved(to point: CGPoint) {
        guard !view.isDragging, !ringOpen else { return }
        let center = discCenter
        let half = Tokens.panelSide / 2
        let freeCenter = CGPoint(x: freeOrigin.x + half, y: freeOrigin.y + half)
        // The free spot counts too, so a disc that moved in from an edge does not flip back.
        let distance = min(hypot(point.x - center.x, point.y - center.y), hypot(point.x - freeCenter.x, point.y - freeCenter.y))
        if holdDock {
            if distance <= Tokens.approach { return }
            holdDock = false
        }
        if distance <= Tokens.diameter / 2 + 4 {
            set(.ready)
        } else if distance <= Tokens.approach {
            set(.awake)
        } else if state == .awake || state == .ready {
            set(.rest)
        }
    }

    private func set(_ newState: State) {
        guard newState != state else { return }
        let oldState = state
        let wasDocked = oldState == .docked
        state = newState
        if newState != .docked { tucked = nil }
        switch newState {
        case .awake, .ready:
            dockTask?.cancel()
            let safe = ringSafeOrigin(freeOrigin)
            if wasDocked || safe != shownOrigin { move(to: safe, spring: .wake) }
            fade(to: 1)
            view.apply(newState, animated: true, waking: wasDocked)
        case .rest:
            if shownOrigin != freeOrigin { move(to: freeOrigin, spring: wasDocked ? .wake : .settle) }
            fade(to: Tokens.restAlpha)
            view.apply(.rest, animated: true)
            scheduleDock()
        case .docked:
            fade(to: Tokens.dockedAlpha)
            view.apply(.docked, animated: true)
        }
    }

    private func fade(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesignTokens.reveal
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }

    // MARK: Docking

    private func scheduleDock() {
        dockTask?.cancel()
        refreshDock()
        dockTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Tokens.dockDelay))
            guard !Task.isCancelled, self.autoHide, self.state == .rest, !self.view.isDragging else { return }
            self.tuck(nearest: self.discCenter)
        }
    }

    /// R80: the tucks and the ring's room on the screen the ball is on.
    private func edges() -> BallEdges? {
        guard let screen = panel.screen ?? NSScreen.main else { return nil }
        let others = NSScreen.screens.filter { $0 != screen }.map(\.frame)
        return BallEdges(frame: screen.frame, visible: screen.visibleFrame, dock: dockFrame, others: others)
    }

    /// R82: tuck into the free spot nearest `point`. False when no edge has room; the ball stays put.
    @discardableResult
    private func tuck(nearest point: CGPoint) -> Bool {
        guard let edges = edges(), let spot = edges.tuck(nearest: point) else { return false }
        tuck(into: spot, edges: edges)
        return true
    }

    /// Tucks into `spot`, which becomes home and is saved; a throw passes the hand's speed on.
    private func tuck(into spot: BallEdges.Tuck, edges: BallEdges, velocity: CGPoint = .zero) {
        let home = Self.origin(forCenter: edges.home(for: spot))
        if home != freeOrigin {
            freeOrigin = home
            onMoved?(home)
        }
        set(.docked)
        tucked = spot
        move(to: Self.origin(forCenter: spot.center), spring: .tuck, velocity: velocity)
    }

    /// R81: read the Dock again, after `delay`. Decisions use the last answer and never wait on this one.
    private func refreshDock(after delay: Duration = .zero) {
        dockRead?.cancel()
        dockRead = Task { @MainActor in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            let frame = await self.reader.dockFrame()
            guard !Task.isCancelled else { return }
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            self.dockFrame = frame.map { Geometry.appKitRect(fromCG: $0, primaryHeight: primaryHeight) }
            self.retuckIfCovered()
        }
    }

    /// R82: a tucked ball whose spot is no longer free (the Dock grew over it, a display came)
    /// moves to the nearest free one.
    private func retuckIfCovered() {
        guard state == .docked, !view.isDragging, !ringOpen, let tucked, let edges = edges(),
              let spot = edges.tuck(nearest: tucked.center), spot != tucked else { return }
        tuck(into: spot, edges: edges)
    }

    /// `origin` (window origin) pulled in far enough for the ring to open fully (R80): from the real
    /// edge beside the Dock, from the visible frame across it and toward the menu bar.
    private func ringSafeOrigin(_ origin: CGPoint) -> CGPoint {
        guard let edges = edges() else { return origin }
        return Self.origin(forCenter: edges.ringSafe(Self.center(forOrigin: origin)))
    }

    /// The disc glides on a spring; the window animator cannot, so `Glide` steps it per frame.
    private func move(to origin: CGPoint, spring: Spring, velocity: CGPoint = .zero) {
        shownOrigin = origin
        glide.move(to: origin, spring: spring, velocity: velocity)
    }

    // MARK: From the view

    func clicked() {
        onPoint?()
    }

    /// R27: mouse down starts the hold; `Ring.Tokens.holdDelay` without a drag opens the ring.
    func pressBegan() {
        refreshDock()
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Ring.Tokens.holdDelay))
            guard !Task.isCancelled, !self.view.isDragging else { return }
            self.ringOpen = true
            self.dockTask?.cancel()
            self.ring.open(at: self.discCenter)
            self.feedback?.tap(.generic)
        }
    }

    /// v0.8.1 R59: every segment, and the center, is a detent.
    func pressMoved(to point: CGPoint) {
        guard ringOpen else { return }
        let before = ring.hovered
        if ring.hover(at: point, commandHeld: NSEvent.modifierFlags.contains(.command)) != before {
            feedback?.tap(.alignment)
        }
    }

    /// Returns true when the release was handled by the ring (chosen or cancelled).
    func pressEnded(at point: CGPoint) -> Bool {
        holdTask?.cancel()
        holdTask = nil
        guard ringOpen else { return false }
        ringOpen = false
        let chosen = ring.hover(at: point, commandHeld: false)
        let commandHeld = NSEvent.modifierFlags.contains(.command)
        ring.close()
        if let chosen { onAction?(chosen, commandHeld && chosen.acceptsClipboardOnly) }
        scheduleDock()
        return true
    }

    /// Absolute: the window sits exactly where the cursor carried it, so nothing accumulates or lags.
    func dragged(to origin: CGPoint) {
        glide.cancel()
        panel.setFrameOrigin(origin)
        freeOrigin = origin
        shownOrigin = origin
        if state == .docked { state = .rest; tucked = nil }
        showGhost()
    }

    /// R84: while a drop would tuck, the ghost shows where.
    private func showGhost() {
        guard autoHide, let edges = edges(), edges.isNearEdge(discCenter),
              let spot = edges.tuck(nearest: discCenter) else {
            ghost.hide()
            return
        }
        ghost.show(at: Self.origin(forCenter: spot.center), below: panel)
    }

    var origin: CGPoint { panel.frame.origin }
    /// AppKit screen frame of the panel, for anchoring a toast to the ball.
    var frame: CGRect { panel.frame }

    /// R83: a drop near an edge tucks into the nearest free spot at once and stays until the cursor
    /// has left; a throw carries on and tucks where it was heading, or comes to rest in open space.
    /// A drop in the open stays ready under the cursor; leaving rests it.
    func dragEnded(velocity: CGPoint) {
        ghost.hide()
        guard let edges = edges() else {
            onMoved?(freeOrigin)
            set(.ready)
            return
        }
        let release = Throw.release(center: discCenter, velocity: velocity, edges: edges, autoHide: autoHide)
        if let spot = release.tuck {
            tuck(into: spot, edges: edges, velocity: release.thrown ? velocity : .zero)
            holdDock = true
        } else if release.thrown {
            freeOrigin = Self.origin(forCenter: release.landing)
            onMoved?(freeOrigin)
            move(to: freeOrigin, spring: .settle, velocity: velocity)
            if state == .rest { scheduleDock() } else { set(.rest) }
        } else {
            onMoved?(freeOrigin)
            set(.ready)
        }
    }
}

/// The window's content: a clear margin around the disc (room for the swell and the shadow) and
/// the mouse handling. Only the disc circle takes a press.
final class BallView: NSView {
    weak var ball: FloatingBall?
    private(set) var isDragging = false
    private var pressed = false
    private var dragStart: CGPoint?
    private var grabOffset: CGPoint = .zero
    private var dragMoved = false
    /// R83: where the cursor was during the drag, for the release's speed.
    private var samples: [Throw.Sample] = []
    private var current: FloatingBall.State = .rest
    let disc: DiscView

    override init(frame frameRect: NSRect) {
        disc = DiscView(frame: frameRect.insetBy(dx: FloatingBall.Tokens.pad, dy: FloatingBall.Tokens.pad))
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(disc)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func onDisc(_ point: CGPoint) -> Bool {
        hypot(point.x - bounds.midX, point.y - bounds.midY) <= FloatingBall.Tokens.diameter / 2 + 2
    }

    /// The ball is never the key window; without this the first click only activates it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func apply(_ state: FloatingBall.State, animated: Bool, waking: Bool = false) {
        current = state
        disc.apply(state, animated: animated, waking: waking)
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        if current == .ready { addCursorRect(disc.frame, cursor: .pointingHand) }
    }

    // MARK: Click and drag

    override func mouseDown(with event: NSEvent) {
        pressed = onDisc(convert(event.locationInWindow, from: nil))
        guard pressed else { return }
        let location = NSEvent.mouseLocation
        dragStart = location
        samples = [Throw.Sample(time: event.timestamp, point: location)]
        let origin = ball?.origin ?? .zero
        grabOffset = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        dragMoved = false
        ball?.pressBegan()
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressed, let start = dragStart else { return }
        let now = NSEvent.mouseLocation
        if ball?.ringOpen == true {
            ball?.pressMoved(to: now)
            return
        }
        samples.append(Throw.Sample(time: event.timestamp, point: now))
        samples.removeAll { event.timestamp - $0.time > 2 * Throw.window }
        if !dragMoved, hypot(now.x - start.x, now.y - start.y) <= 6 { return }
        dragMoved = true
        isDragging = true
        ball?.dragged(to: CGPoint(x: now.x - grabOffset.x, y: now.y - grabOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard pressed else { return }
        defer { pressed = false; dragStart = nil; isDragging = false; samples = [] }
        if ball?.pressEnded(at: NSEvent.mouseLocation) == true { return }
        if dragMoved {
            samples.append(Throw.Sample(time: event.timestamp, point: NSEvent.mouseLocation))
            ball?.dragEnded(velocity: Throw.velocity(samples))
        } else {
            ball?.clicked()
        }
    }
}

/// The glass disc. On macOS 26 it is the system's glass, refracting what sits behind it, so it
/// belongs to any background; earlier systems get the hud material thinned to the center with a
/// faint rim. Over the glass: a soft light at the center that drifts slowly (`ball.glow`), and the
/// pointing hand that fades in when awake. Ready tints the glass with the accent. Motion is quiet:
/// a slight swell under the cursor and a tuck when docked on a critically damped spring, and a
/// small swell from below size only when the disc comes out of an edge.
final class DiscView: NSView {
    private let glow = CAGradientLayer()
    private let glowHost = NSView()
    private let icon = NSImageView()
    private var glass: NSView?
    private let fallback = NSVisualEffectView()
    private let fallbackRim = CAGradientLayer()
    private var scale: CGFloat = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let radius = bounds.width / 2

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .clear // the liquid one: the background shows through the middle
            glass.cornerRadius = radius
            glass.autoresizingMask = [.width, .height]
            addSubview(glass)
            self.glass = glass
        } else {
            fallback.material = .hudWindow
            fallback.blendingMode = .behindWindow
            fallback.state = .active
            fallback.frame = bounds
            fallback.wantsLayer = true
            fallback.layer?.cornerRadius = radius
            fallback.layer?.masksToBounds = true
            fallback.layer?.borderWidth = 1
            fallback.maskImage = Self.radialMask(size: bounds.size, center: 0.25)
            addSubview(fallback)
            fallbackRim.frame = bounds
            fallbackRim.startPoint = CGPoint(x: 0.1, y: 0.9)
            fallbackRim.endPoint = CGPoint(x: 0.9, y: 0.1)
            fallbackRim.locations = [0, 0.5, 0.8]
            let ring = CAShapeLayer()
            ring.frame = bounds
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 1.5, dy: 1.5), transform: nil)
            ring.fillColor = nil
            ring.strokeColor = NSColor.black.cgColor
            ring.lineWidth = 1
            fallbackRim.mask = ring
            fallback.layer?.addSublayer(fallbackRim)
        }

        // A radial gradient whose ellipse touches its bounds fades to clear before any edge.
        glow.type = .radial
        glow.frame = bounds
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.locations = [0, 1]
        glowHost.layer = glow
        glowHost.wantsLayer = true
        glowHost.frame = bounds
        addSubview(glowHost)

        icon.frame = bounds.insetBy(dx: FloatingBall.Tokens.iconInset, dy: FloatingBall.Tokens.iconInset)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.alphaValue = 0
        icon.image = Self.handImage
        icon.contentTintColor = .labelColor
        addSubview(icon)
        applyColors()
        startGlow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The pointing hand the disc shows awake; the ring's center uses the same one.
    static var handImage: NSImage? {
        guard let image = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: "Point") else { return nil }
        image.isTemplate = true
        return image.withSymbolConfiguration(.init(pointSize: 18, weight: .medium))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private var isReady = false

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let light = NSColor.white
            glow.colors = [light.withAlphaComponent(FloatingBall.Tokens.glowAlpha).cgColor, light.withAlphaComponent(0).cgColor]
            if #available(macOS 26.0, *), let glass = glass as? NSGlassEffectView {
                glass.tintColor = isReady ? NSColor.controlAccentColor.withAlphaComponent(0.28) : nil
            } else {
                fallbackRim.colors = [light.withAlphaComponent(0.6).cgColor, light.withAlphaComponent(0.15).cgColor, light.withAlphaComponent(0).cgColor]
                fallback.layer?.borderColor = isReady ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
            }
        }
    }

    /// Alpha mask for the fallback material: `center` at the middle rising to full at the rim.
    private static func radialMask(size: CGSize, center: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let gradient = NSGradient(colorsAndLocations:
                (NSColor.black.withAlphaComponent(center), 0),
                (NSColor.black.withAlphaComponent(center + (1 - center) * 0.5), 0.7),
                (NSColor.black, 1)
            ) else { return false }
            gradient.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
    }

    /// The ghost (specs/ball-edges.md R84) is the glass alone, without the drifting light.
    func hideGlow() {
        glow.removeAnimation(forKey: "glow")
        glow.opacity = 0
    }

    /// `ball.glow`: the center light drifts `glowLow` → `glowHigh` → `glowLow` over 6 s; steady under Reduce Motion.
    private func startGlow() {
        glow.removeAnimation(forKey: "glow")
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { glow.opacity = 0.7; return }
        glow.opacity = FloatingBall.Tokens.glowLow
        let drift = CAKeyframeAnimation(keyPath: "opacity")
        drift.values = [FloatingBall.Tokens.glowLow, FloatingBall.Tokens.glowHigh, FloatingBall.Tokens.glowLow]
        drift.keyTimes = [0, 0.5, 1]
        drift.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        drift.duration = FloatingBall.Tokens.glowPeriod
        drift.repeatCount = .infinity
        glow.add(drift, forKey: "glow")
    }

    func apply(_ state: FloatingBall.State, animated: Bool, waking: Bool) {
        isReady = state == .ready
        applyColors()
        if state == .docked || state == .rest {
            startGlow()
        } else {
            glow.removeAnimation(forKey: "glow")
            glow.opacity = 0.5
        }
        let showIcon: CGFloat = (state == .awake || state == .ready) ? 1 : 0
        let appearing = showIcon == 1 && icon.alphaValue == 0
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DesignTokens.reveal
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                icon.animator().alphaValue = showIcon
            }
            if appearing { settleIcon() }
        } else {
            icon.alphaValue = showIcon
        }
        let target: CGFloat = switch state {
        case .ready: FloatingBall.Tokens.hoverScale
        case .docked: FloatingBall.Tokens.dockedScale
        case .awake, .rest: 1
        }
        setScale(target, from: waking ? FloatingBall.Tokens.wakeFromScale : nil, animated: animated)
    }

    // MARK: Motion

    /// The disc's size follows the state on the system spring; `from` starts a wake below size.
    private func setScale(_ target: CGFloat, from: CGFloat?, animated: Bool) {
        guard let layer, target != scale || from != nil else { return }
        let end = centeredScale(target, in: bounds)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !animated || reduceMotion {
            layer.transform = end
            scale = target
            return
        }
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = from.map { centeredScale($0, in: bounds) } ?? layer.presentation()?.transform ?? layer.transform
        spring.toValue = end
        spring.mass = 1
        spring.stiffness = Spring.hover.stiffness
        spring.damping = Spring.hover.dampingCoefficient
        spring.duration = spring.settlingDuration
        layer.transform = end
        scale = target
        layer.add(spring, forKey: "scale")
    }

    /// The hand settles from a touch under size as it fades in; the fade carries the moment.
    private func settleIcon() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let iconLayer = icon.layer else { return }
        let settle = CASpringAnimation(keyPath: "transform")
        settle.fromValue = centeredScale(0.92, in: icon.bounds)
        settle.toValue = CATransform3DIdentity
        settle.mass = 1
        settle.stiffness = Spring.hover.stiffness
        settle.damping = Spring.hover.dampingCoefficient
        settle.duration = settle.settlingDuration
        iconLayer.add(settle, forKey: "settle")
    }
}
