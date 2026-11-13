import AppKit

/// specs/source-hints.md R155: whether a name is one of the system's SF Symbols. SwiftUI publishes the
/// symbol's name as the accessibility identifier of a button drawn with `Image(systemName:)`, so
/// `gearshape` on a button is the picture's name, not an identifier anyone declared.
enum SymbolCatalog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var known: [String: Bool] = [:]

    static func contains(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let answer = known[name] { return answer }
        let answer = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        known[name] = answer
        return answer
    }
}
