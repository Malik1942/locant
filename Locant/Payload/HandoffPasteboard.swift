import AppKit
import Synchronization

/// specs/handoff.md R81: the clipboard during a hand-off. Each paste gets an item of one type, offered lazily and
/// marked transient so clipboard histories skip it; the receiving app's read of that type is the
/// receipt. Every write here is noted, so a copy of the user's, which moves the change count, stops the
/// hand-off, and `restore` puts Return's item back whenever a temporary one would otherwise stay.
@MainActor
final class HandoffPasteboard {
    /// nspasteboard.org's marker for data that should not enter a clipboard history. Measured Oct 1,
    /// 2026: without it something on the Mac read a new item 0.7 s after it was written; with it, nothing.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let pasteboard: NSPasteboard
    private let receiptLimit: Duration
    private let earlyReadWait: Duration
    private var ownCount: Int
    private var provider: OneTypeProvider?
    private var readEarly = false
    /// True while the clipboard holds a temporary item of this hand-off's.
    private(set) var holdsTemporary = false

    /// Made right after Return's write, so the count it notes is Return's.
    init(pasteboard: NSPasteboard = .general, receiptLimit: Duration = .seconds(1), earlyReadWait: Duration = .milliseconds(300)) {
        self.pasteboard = pasteboard
        self.receiptLimit = receiptLimit
        self.earlyReadWait = earlyReadWait
        ownCount = pasteboard.changeCount
    }

    /// The clipboard is still what Locant wrote last.
    var isOwn: Bool { pasteboard.changeCount == ownCount }

    /// One type, provided when asked, transient. Written right before its ⌘V, so nothing else has time
    /// to read it first.
    func offer(_ data: Data, as type: NSPasteboard.PasteboardType) {
        let provider = OneTypeProvider(data: data)
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [type])
        item.setData(Data(), forType: Self.transientType)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        ownCount = pasteboard.changeCount
        self.provider = provider
        readEarly = false
        holdsTemporary = true
    }

    /// Just before ⌘V: reads from now on are the receiver's.
    func arm() {
        readEarly = provider?.arm() ?? false
    }

    /// After ⌘V: true when the receiver read the type within the limit. A read before `arm()` (a
    /// history that ignores the marker) left the data cached, so no read can come: wait instead.
    /// A read is not a keep: this times the next step and never judges what landed.
    func receipt() async -> Bool {
        guard let provider else { return false }
        if readEarly {
            try? await Task.sleep(for: earlyReadWait)
            return true
        }
        return await provider.waitForRead(limit: receiptLimit)
    }

    /// Return's item again, eagerly and not transient (R8), while the clipboard is still Locant's and
    /// holds a temporary item.
    func restore(markdown: String, png: Data) {
        guard isOwn, holdsTemporary else { return }
        PasteboardWriter.write(markdown: markdown, png: png, to: pasteboard)
        ownCount = pasteboard.changeCount
        holdsTemporary = false
    }
}

/// One type, provided when the pasteboard asks; tells a read before the ⌘V from the receiver's. AppKit
/// calls the provider on the main thread for another app's read and on the reading thread for this
/// process's own, so the state sits behind a lock.
final class OneTypeProvider: NSObject, NSPasteboardItemDataProvider, Sendable {
    private struct State {
        var armed = false
        var early = false
        var read = false
        var waiter: CheckedContinuation<Bool, Never>?
    }

    private let data: Data
    private let state = Mutex(State())

    init(data: Data) {
        self.data = data
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        item.setData(data, forType: type)
        let waiter = state.withLock { state -> CheckedContinuation<Bool, Never>? in
            guard state.armed else {
                state.early = true
                return nil
            }
            state.read = true
            let waiter = state.waiter
            state.waiter = nil
            return waiter
        }
        waiter?.resume(returning: true)
    }

    /// Marks the ⌘V. True when the type had been read before it.
    func arm() -> Bool {
        state.withLock { state in
            state.armed = true
            return state.early
        }
    }

    /// The receiver's read, up to `limit`.
    func waitForRead(limit: Duration) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let readAlready = state.withLock { state -> Bool in
                if state.read { return true }
                state.waiter = continuation
                return false
            }
            if readAlready {
                continuation.resume(returning: true)
                return
            }
            Task {
                try? await Task.sleep(for: limit)
                let pending = self.state.withLock { state -> CheckedContinuation<Bool, Never>? in
                    let waiter = state.waiter
                    state.waiter = nil
                    return waiter
                }
                pending?.resume(returning: false)
            }
        }
    }
}
