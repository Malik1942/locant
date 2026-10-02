import AppKit

/// specs/ball-edges.md R84: where a release will tuck the ball. The disc's glass, faint, with no
/// hand and no glow, in a panel of its own just under the ball; it never takes the mouse.
@MainActor
final class BallGhost {
    static let alpha: CGFloat = 0.35

    private let panel: NSPanel
    private var shown = false

    init() {
        let side = FloatingBall.Tokens.panelSide
        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        panel = NSPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let content = NSView(frame: bounds)
        let disc = DiscView(frame: bounds.insetBy(dx: FloatingBall.Tokens.pad, dy: FloatingBall.Tokens.pad))
        disc.hideGlow()
        content.addSubview(disc)
        panel.contentView = content
    }

    /// `origin`: the window origin the ball will have once tucked there. Moves without a glide.
    func show(at origin: CGPoint, below ball: NSWindow) {
        panel.setFrameOrigin(origin)
        guard !shown else { return }
        shown = true
        panel.alphaValue = 0
        panel.order(.below, relativeTo: ball.windowNumber)
        fade(to: Self.alpha, over: DesignTokens.reveal)
    }

    func hide() {
        guard shown else { return }
        shown = false
        fade(to: 0, over: DesignTokens.dismiss)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(DesignTokens.dismiss * 1000) + 20))
            if !self.shown { self.panel.orderOut(nil) }
        }
    }

    private func fade(to alpha: CGFloat, over duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }
}
