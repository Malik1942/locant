import Foundation

/// Section 5: `Capture` → Markdown for the clipboard. Pure; derived from the JSON, never the reverse.
enum MarkdownBuilder {
    static func build(_ capture: Capture) -> String {
        var sections: [String] = ["## Locant capture (\(capture.mode.rawValue))"]
        let note = noteBlock(capture.note)
        let extras = [elementsBlock(capture), nearbyBlock(capture), textBlock(capture)].compactMap { $0 }
        // v0.8 R58: a set selected with Shift is numbered; "this" and "that" match how notes are worded.
        let elementBlocks = capture.targets.map { targets in targets.enumerated().map { targetBlock($1, index: $0, capture: capture) } }
            ?? [elementBlock(capture.element)]
        switch capture.mode {
        case .fix:
            sections.append(sourceBlock(capture))
            sections.append(contentsOf: elementBlocks)
            sections.append(contentsOf: extras)
            if let note { sections.append(note) }
        case .reference:
            if let note { sections.append(note) }
            sections.append(sourceBlock(capture))
            sections.append(contentsOf: elementBlocks)
            sections.append(contentsOf: extras)
        }
        // The heading sits directly on the first block (section 5); blocks are separated by a blank line.
        let heading = sections.removeFirst()
        return heading + "\n" + sections.joined(separator: "\n\n") + "\n"
    }

    // MARK: Blocks

    private static func sourceBlock(_ capture: Capture) -> String {
        let source = capture.source
        let bundleId = source.simulator?.appBundleId ?? source.app.bundleId
        let windowTitle = source.window?.title ?? "none"
        let region = "\(number(capture.image.widthPt))×\(number(capture.image.heightPt)) pt @\(number(capture.image.scale))x"
        let regionNote = capture.elements != nil ? "drawn frame"
            : capture.targets != nil ? (capture.targets!.contains { $0.imagePath != nil } ? "element 1 + \(number(Geometry.cropPadding)) pt; the others have their own images" : "\(capture.targets!.count) elements + \(number(Geometry.cropPadding)) pt")
            : capture.element == nil ? "around the click point" : "element + \(number(Geometry.cropPadding)) pt"
        var lines = [
            "Image: \(capture.image.path)",
            "App: \(source.app.name) (\(bundleId)) · Window: \(windowTitle)",
            "Captured: \(capturedText(capture.createdAt)) · Image region: \(region) (\(regionNote))",
        ]
        if let url = source.url { lines.append("URL: \(url)") }
        if let root = source.projectRoot {
            lines.append("Project: \(root)")
            lines.append(projectAdvice)
        }
        return lines.joined(separator: "\n")
    }

    /// v0.9.1: the Project line as a bare path went unread. An agent working in another checkout of the same repo
    /// (a worktree, a clone) found a look-alike in its own copy and changed that, never the code on screen.
    static let projectAdvice = "The app on screen was built from this folder. If you are working in a different checkout of this repo (another worktree or clone), your copy is not the code on screen: change it in this folder, or ask which copy to change."

    /// One numbered element of a set: its own app, window, and image when they differ from the capture's.
    private static func targetBlock(_ target: CaptureTarget, index: Int, capture: Capture) -> String {
        let heading = "### Element \(index + 1)" + (index == 0 ? " (this)" : index == 1 ? " (that)" : "")
        var lines = [heading]
        if target.app.bundleId != capture.source.app.bundleId || target.window?.title != capture.source.window?.title {
            lines.append("App: \(target.app.name) (\(target.app.bundleId)) · Window: \(target.window?.title ?? "none")")
        }
        if let url = target.url, url != capture.source.url { lines.append("URL: \(url)") }
        if let path = target.imagePath { lines.append("Image: \(path)") }
        lines.append(contentsOf: elementLines(target.element))
        return lines.joined(separator: "\n")
    }

    private static func elementBlock(_ element: ResolvedElement?) -> String {
        guard let element else {
            return "### Target element\nNo element information available (app exposes no accessibility tree). Use the image.\nIf this view is yours, give it .accessibilityElement() and .accessibilityIdentifier(\"…\") so Locant can point at it next time."
        }
        return (["### Target element"] + elementLines(element)).joined(separator: "\n")
    }

    /// The lines under an element heading: the head line, advice, value, frame, and path.
    private static func elementLines(_ element: ResolvedElement) -> [String] {
        if element.role == ElementResolver.clusterRole {
            let members = element.members ?? []
            var lines = [
                "cluster · \(members.count) elements (visual grouping computed by Locant, not an accessibility element; frame approximate)",
                "Members: " + members.map(memberText).joined(separator: " · "),
            ]
            let f = element.frame
            lines.append("Frame: x=\(number(f.x)) y=\(number(f.y)) w=\(number(f.w)) h=\(number(f.h))")
            lines.append("Path: " + element.path.map(pathText).joined(separator: " > "))
            return lines
        }
        var head = element.role
        if let label = element.label { head += " \"\(label)\"" }
        if let identifier = element.identifier {
            head += " · id=\(identifier)"
            if element.identifierSource == .possiblySymbolName {
                head += " (may be a symbol name, not a declared identifier)"
            }
        }
        // v0.8: the DOM's handles, beside or instead of the accessibility identifier.
        if let dom = element.dom {
            if let id = dom.id { head += " · #\(id)" }
            if !dom.classes.isEmpty {
                head += " · ." + dom.classes.prefix(Self.classLimit).joined(separator: ".")
                if dom.classes.count > Self.classLimit { head += " (+\(dom.classes.count - Self.classLimit) more)" }
            }
        }
        let hasHandle = element.identifier != nil || element.dom?.id != nil || !(element.dom?.classes.isEmpty ?? true)
        if !hasHandle { head += " · no identifier" }
        var lines = [head]
        if element.identifier == nil, element.dom == nil {
            lines.append("No identifier. Grep the label text; add .accessibilityIdentifier(\"…\") to this view so the next capture is exact.")
        } else if element.identifier == nil, element.dom?.id == nil {
            lines.append(hasHandle
                ? "No id attribute. Grep the class names or the label text; give the element an id so the next capture is exact."
                : "No id or class. Grep the label text; give the element an id so the next capture is exact.")
        }
        if let value = element.value { lines.append("Value: \(valueText(value))") }
        let f = element.frame
        lines.append("Frame: x=\(number(f.x)) y=\(number(f.y)) w=\(number(f.w)) h=\(number(f.h))")
        lines.append("Path: " + element.path.map(pathText).joined(separator: " > "))
        return lines
    }

    // v0.2 blocks

    private static func elementsBlock(_ capture: Capture) -> String? {
        guard let elements = capture.elements else { return nil }
        guard !elements.isEmpty else { return "### Elements in frame (0)\nNo accessibility elements inside the frame." }
        return (["### Elements in frame (\(elements.count))"] + elements.map { regionLine($0, suffix: nil) }).joined(separator: "\n")
    }

    private static func nearbyBlock(_ capture: Capture) -> String? {
        guard let nearby = capture.nearby, !nearby.isEmpty, let crop = capture.image.crop else { return nil }
        let center = CGPoint(x: crop.x + crop.w / 2, y: crop.y + crop.h / 2)
        return (["### Nearby"] + nearby.map { regionLine($0, suffix: RegionResolver.offsetText(from: center, to: $0.frame.cgRect)) }).joined(separator: "\n")
    }

    private static func textBlock(_ capture: Capture) -> String? {
        guard let ocr = capture.ocr, !ocr.isEmpty else { return nil }
        return "### Text in image\n" + ocr
    }

    private static func regionLine(_ e: RegionElement, suffix: String?) -> String {
        var text = e.role
        if let label = e.label { text += " \"\(label)\"" }
        if let identifier = e.identifier {
            text += " · id=\(identifier)"
            if e.identifierSource == .possiblySymbolName { text += " (may be a symbol name)" }
        }
        if let suffix {
            text += " · \(suffix)"
        } else {
            text += " · x=\(number(e.frame.x)) y=\(number(e.frame.y)) w=\(number(e.frame.w)) h=\(number(e.frame.h))"
        }
        return text
    }

    private static func noteBlock(_ note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "### Note\n\(trimmed)"
    }

    // MARK: Formatting

    private static func memberText(_ member: ElementMember) -> String {
        var text = member.role
        if let label = member.label { text += " \"\(label)\"" }
        if let identifier = member.identifier { text += "#\(identifier)" }
        return text
    }

    /// How many class names the element line shows before "(+n more)".
    static let classLimit = 6

    private static func pathText(_ entry: PathEntry) -> String {
        if let identifier = entry.identifier { return "\(entry.role)#\(identifier)" }
        if let dom = entry.dom { return entry.role + dom }
        return entry.role
    }

    private static func valueText(_ value: ElementValue) -> String {
        switch value {
        case .string(let s): "\"\(s)\""
        case .number(let d): number(d)
        case .bool(let b): b ? "true" : "false"
        }
    }

    /// "2026-09-12T14:03:12-07:00" → "2026-09-12 14:03"
    static func capturedText(_ createdAt: String) -> String {
        guard createdAt.count >= 16 else { return createdAt }
        return String(createdAt.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }

    /// Rounded to one decimal; integers print without a fraction (57.9999 → 58, 893.67 → 893.7).
    static func number(_ d: Double) -> String {
        let tenths = (d * 10).rounded() / 10
        return tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)
    }
}
