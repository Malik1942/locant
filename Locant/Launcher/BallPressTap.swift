import AppKit
import ApplicationServices

/// specs/frozen-screen.md R122: a session event tap on the left mouse button, kept while the ball
/// is awake. An open menu closes on any press outside it, the ball's included, before Point could
/// freeze it; a press this tap takes reaches no app, so the menu stays open. Needs Accessibility
/// trust, which Locant already requires; without it `init` fails and the ball takes presses as
/// any window does.
@MainActor
final class BallPressTap {
    enum Kind: Sendable { case down, dragged, up }

    /// Returns true to take the event. The location is in CG coordinates.
    private let handler: @MainActor (Kind, CGPoint) -> Bool
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init?(handler: @escaping @MainActor (Kind, CGPoint) -> Bool) {
        self.handler = handler
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<BallPressTap>.fromOpaque(refcon).takeUnretainedValue()
            let kind: Kind
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                MainActor.assumeIsolated { tap.enable() }
                return Unmanaged.passUnretained(event)
            case .leftMouseDown: kind = .down
            case .leftMouseDragged: kind = .dragged
            case .leftMouseUp: kind = .up
            default: return Unmanaged.passUnretained(event)
            }
            let location = event.location
            let take = MainActor.assumeIsolated { tap.handler(kind, location) }
            return take ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return nil }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        enable()
    }

    private func enable() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
    }
}
