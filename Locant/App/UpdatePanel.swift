import AppKit

/// specs/in-app-update.md R177: the small panel while an update downloads and is checked. Cancel stops
/// it; nothing else is shown after a cancel.
@MainActor
final class UpdatePanel: NSObject {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private var onCancel: (@MainActor () -> Void)?

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 110), styleMask: [.titled], backing: .buffered, defer: true)
        super.init()
        panel.title = "Locant Update"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 1
        bar.isIndeterminate = true
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.keyEquivalent = "\u{1b}"
        let stack = NSStackView(views: [label, bar, cancel])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        label.widthAnchor.constraint(equalToConstant: 320).isActive = true
        bar.widthAnchor.constraint(equalToConstant: 320).isActive = true
        panel.contentView = stack
    }

    func show(_ text: String, onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
        setText(text)
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// A new step: the bar spins until progress arrives.
    func setText(_ text: String) {
        label.stringValue = text
        setProgress(nil)
    }

    /// nil while the size is unknown.
    func setProgress(_ fraction: Double?) {
        if let fraction {
            bar.stopAnimation(nil)
            bar.isIndeterminate = false
            bar.doubleValue = fraction
        } else {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
    }

    func close() {
        onCancel = nil
        bar.stopAnimation(nil)
        panel.orderOut(nil)
    }

    @objc private func cancelClicked() {
        let cancel = onCancel
        close()
        cancel?()
    }
}
