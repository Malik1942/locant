import AppKit

/// R8: one pasteboard item carrying both the PNG and the Markdown. Called only after the files are
/// on disk, so a failed capture never touches the clipboard.
@MainActor
enum PasteboardWriter {
    /// Snap and Cut: the image alone.
    static func write(png: Data) {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// Text and Color: a string alone.
    static func write(string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// specs/handoff.md R81: `pasteboard` is the general one except in tests.
    static func write(markdown: String, png: Data, to pasteboard: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString(markdown, forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
