import AppKit

/// R1/R29: the hotkeys. Each binding is a double-tap of one modifier within 350 ms (Control by
/// default, for Point) or a chord (⌃⌥ and a digit by default, one per action). One event tap
/// serves every binding: a matched chord is swallowed so it never also reaches the frontmost app;
/// double-taps pass through, since a modifier press is harmless. Without Accessibility trust the
/// tap cannot be made and `NSEvent` monitors observe instead.
@MainActor
final class HotkeyMonitor {
    struct Binding {
        let hotkey: Hotkey
        let fire: @MainActor () -> Void

        init(_ hotkey: Hotkey, fire: @escaping @MainActor () -> Void) {
            self.hotkey = hotkey
            self.fire = fire
        }
    }

    static let window: TimeInterval = 0.35
    private static let rightCommandKeyCode: UInt16 = 54
    private static let all: NSEvent.ModifierFlags = [.control, .command, .option, .shift]

    let bindings: [Binding]
    private var tap: KeyEventTap?
    private var monitors: [Any] = []
    private var heldModifiers: NSEvent.ModifierFlags = []
    private var lastTap: (modifier: HotkeyModifier, rightKey: Bool, time: TimeInterval)?

    /// specs/handoff.md R83: every key the tap sees, before the hotkeys and before the frontmost app; it only
    /// looks. Not called without the tap: a monitor hears a key after the app has it.
    var onKey: ((KeyEventTap.KeyEvent) -> Void)?

    /// True while the tap is in place, so matched chords stop at Locant.
    var swallowsChords: Bool { tap != nil }

    init(bindings: [Binding]) {
        self.bindings = bindings
    }

    /// One binding, for the tests and the simple case.
    convenience init(hotkey: Hotkey, onFire: @escaping @MainActor () -> Void) {
        self.init(bindings: [Binding(hotkey, fire: onFire)])
    }

    func start() {
        guard tap == nil, monitors.isEmpty, !bindings.isEmpty else { return }
        heldModifiers = []
        lastTap = nil
        if let tap = KeyEventTap(handler: { [weak self] event in
            self?.onKey?(event)
            return self?.handle(event) ?? false
        }) {
            self.tap = tap
            return
        }
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            guard let keyEvent = KeyEventTap.KeyEvent(event) else { return }
            MainActor.assumeIsolated { _ = self?.handle(keyEvent) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            guard let keyEvent = KeyEventTap.KeyEvent(event) else { return event }
            let swallow = MainActor.assumeIsolated { self?.handle(keyEvent) ?? false }
            return swallow ? nil : event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        tap?.stop()
        tap = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        heldModifiers = []
        lastTap = nil
    }

    /// Returns true when the event was one of our chords, so the caller swallows it.
    func handle(_ event: KeyEventTap.KeyEvent) -> Bool {
        switch event.kind {
        case .flagsChanged:
            handleFlags(event.flags, keyCode: event.keyCode, timestamp: event.timestamp)
            return false
        case .keyDown:
            return handleKey(event.flags, keyCode: event.keyCode, isRepeat: event.isRepeat)
        }
    }

    // MARK: Double-tap

    /// Fires on the second rising edge of the same modifier inside the window, with no other
    /// modifier held at either press.
    func handleFlags(_ flags: NSEvent.ModifierFlags, keyCode: UInt16, timestamp: TimeInterval) {
        let held = flags.intersection(Self.all)
        let rising = held.subtracting(heldModifiers)
        heldModifiers = held
        guard !rising.isEmpty else { return }
        guard rising == held, let modifier = Self.modifier(for: rising) else {
            lastTap = nil
            return
        }
        let rightKey = modifier == .command && keyCode == Self.rightCommandKeyCode
        if let last = lastTap, last.modifier == modifier, timestamp - last.time <= Self.window {
            lastTap = nil
            let bothRight = last.rightKey && rightKey
            for binding in bindings {
                switch binding.hotkey {
                case .doubleTap(let wanted) where wanted == modifier: binding.fire()
                case .doubleTap(.rightCommand) where modifier == .command && bothRight: binding.fire()
                default: break
                }
            }
        } else {
            lastTap = (modifier, rightKey, timestamp)
        }
    }

    // MARK: Chord

    /// Returns true when the key with these modifiers is a bound chord (and fires it, unless the
    /// key is auto-repeating: a held chord fires once and stays swallowed).
    @discardableResult
    func handleKey(_ flags: NSEvent.ModifierFlags, keyCode: UInt16, isRepeat: Bool = false) -> Bool {
        let matched = bindings.filter { binding in
            if case .chord(let wantedCode, let wantedModifiers, _) = binding.hotkey {
                return Self.matches(keyCode: keyCode, flags: flags, wantedCode: wantedCode, wantedModifiers: wantedModifiers)
            }
            return false
        }
        guard !matched.isEmpty else { return false }
        if !isRepeat {
            for binding in matched { binding.fire() }
        }
        return true
    }

    static func matches(keyCode: UInt16, flags: NSEvent.ModifierFlags, wantedCode: UInt16, wantedModifiers: KeyModifiers) -> Bool {
        keyCode == wantedCode && KeyModifiers(flags) == wantedModifiers
    }

    /// The one modifier in `flags`; nil for none or several. Right Command is told apart by key code, not flag.
    static func modifier(for flags: NSEvent.ModifierFlags) -> HotkeyModifier? {
        switch flags {
        case [.control]: .control
        case [.option]: .option
        case [.shift]: .shift
        case [.command]: .command
        default: nil
        }
    }
}

extension KeyModifiers {
    /// The four chord modifiers from an event; Caps Lock and Fn are ignored.
    init(_ flags: NSEvent.ModifierFlags) {
        var set = KeyModifiers()
        if flags.contains(.control) { set.insert(.control) }
        if flags.contains(.option) { set.insert(.option) }
        if flags.contains(.shift) { set.insert(.shift) }
        if flags.contains(.command) { set.insert(.command) }
        self = set
    }
}
