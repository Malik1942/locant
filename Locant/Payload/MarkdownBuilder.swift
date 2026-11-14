import Foundation

/// Section 5: `Capture` → Markdown for the clipboard. Pure; derived from the JSON, never the reverse.
enum MarkdownBuilder {
    static func build(_ capture: Capture) -> String {
        var sections: [String] = ["## Locant capture (\(capture.mode.rawValue))"]
        let extras = [elementsBlock(capture), nearbyBlock(capture), textBlock(capture)].compactMap { $0 }
        // v0.8 R58: a set selected with Shift is numbered; "this" and "that" match how notes are worded.
        let elementBlocks = capture.targets.map { targets in targets.enumerated().map { targetBlock($1, index: $0, capture: capture) } }
            ?? [elementBlock(capture.element, mode: capture.mode, mirrored: capture.source.simulator != nil, web: isWeb(capture.source))]
        // specs/v0.7.1.md R55: the image path leads in both modes, so a terminal agent that receives only the text
        // can open the PNG; the note closes the payload. v0.1 had a reference capture lead with the note; amended
        // 2026-11-02, since the MCP server, the README, and the skill all promise the path first.
        sections.append(sourceBlock(capture))
        sections.append(contentsOf: elementBlocks)
        sections.append(contentsOf: extras)
        if let note = noteBlock(capture.note) { sections.append(note) }
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
        let mirrored = capture.source.simulator != nil && target.app.bundleId == capture.source.app.bundleId
        lines.append(contentsOf: elementLines(target.element, mode: capture.mode, mirrored: mirrored))
        return lines.joined(separator: "\n")
    }

    /// A page in a browser: its address is known, or the app is one of the browsers Locant can ask.
    static func isWeb(_ source: SourceInfo) -> Bool {
        source.url != nil || WebSourceLocator.browser(bundleId: source.app.bundleId) != nil
    }

    static let noElementLine = "No element information available (app exposes no accessibility tree). Use the image."
    static let noElementAdvice = "If this view is yours, give it .accessibilityElement() and .accessibilityIdentifier(\"…\") so Locant can point at it next time."
    /// The same advice for a page: SwiftUI's modifiers mean nothing there.
    static let noElementWebAdvice = "If this page is yours, give the element an id so Locant can point at it next time."

    private static func elementBlock(_ element: ResolvedElement?, mode: CaptureMode, mirrored: Bool, web: Bool) -> String {
        guard let element else {
            return "### Target element\n\(noElementLine)\n\(web ? noElementWebAdvice : noElementAdvice)"
        }
        return (["### Target element"] + elementLines(element, mode: mode, mirrored: mirrored)).joined(separator: "\n")
    }

    /// The lines under an element heading: the head line, advice, value, frame, and path. `mirrored`: the
    /// element is inside a simulated device, so the window around it belongs to the Simulator or Device Hub.
    private static func elementLines(_ element: ResolvedElement, mode: CaptureMode, mirrored: Bool) -> [String] {
        let path = pathLine(element.path, mirrored: mirrored)
        if element.role == ElementResolver.clusterRole {
            let members = element.members ?? []
            // specs/capture-shapes.md R129: a shape's frame is the edges seen on screen; a cluster's, an estimate.
            // R132: a group's frame is the union of its controls.
            let kind = switch element.rawRole {
            case ElementResolver.shapeRawRole: "shape found on screen by Locant, not an accessibility element; frame from its visible edges"
            case ElementResolver.groupRawRole: "controls in one row or column, grouped by Locant, not an accessibility element; frame is their union"
            default: "visual grouping computed by Locant, not an accessibility element; frame approximate"
            }
            var lines = [
                "cluster · \(members.count) elements (\(kind))",
                "Members: " + members.map(memberText).joined(separator: " · "),
            ]
            let f = element.frame
            if let hint = element.sourceHint { lines.insert(sourceLine(hint, element: element), at: 2) }
            lines.append("Frame: x=\(number(f.x)) y=\(number(f.y)) w=\(number(f.w)) h=\(number(f.h))")
            if let path { lines.append(path) }
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
        // specs/source-hints.md R160: where Locant found the element in the project takes the place of the
        // advice to grep for it.
        if let hint = element.sourceHint {
            if element.rawRole == ElementResolver.textRawRole { lines.append(Self.textLineNote) }
            lines.append(sourceLine(hint, element: element))
        } else if element.rawRole == ElementResolver.textRawRole {
            // specs/capture-shapes.md R135: a line Locant read inside an element that merges its lines. It is no view
            // of its own, so no identifier can be added to it.
            lines.append(Self.textLineNote)
            lines.append(Self.textLineAdvice)
        } else if element.component?.source != nil {
            // specs/web-source.md R150: the page named the line; no grep advice needed.
        } else if element.identifier == nil, element.dom == nil {
            lines.append(missingHandleLine("No identifier.", mode: mode,
                                           fix: "Grep the label text; add .accessibilityIdentifier(\"…\") to this view so the next capture is exact."))
        } else if element.identifier == nil, element.dom?.id == nil, element.dom?.parent == nil {
            lines.append(hasHandle
                ? missingHandleLine("No id attribute.", mode: mode, fix: "Grep the class names or the label text; give the element an id so the next capture is exact.")
                : missingHandleLine("No id or class.", mode: mode, fix: "Grep the label text; give the element an id so the next capture is exact."))
        }
        // specs/source-hints.md R171: a text node's handles are its parent's.
        if let parent = element.dom?.parent { lines.append(insideLine(parent, text: element.rawRole == SourceHints.staticTextRole)) }
        if let component = element.component { lines.append(contentsOf: componentLines(component)) }
        if let row = element.row { lines.append(positionLine(row)) }
        if let value = element.value { lines.append("Value: \(valueText(value))") }
        let f = element.frame
        lines.append("Frame: x=\(number(f.x)) y=\(number(f.y)) w=\(number(f.w)) h=\(number(f.h))")
        if let path { lines.append(path) }
        return lines
    }

    /// specs/source-hints.md R162: in a simulated device the first steps of the path are the Simulator's or
    /// Device Hub's own window, which says nothing about the app. They are left out, and so is a path that
    /// then names nothing. A path with no such step is shown whole.
    static func pathLine(_ path: [PathEntry], mirrored: Bool) -> String? {
        guard mirrored, let host = path.lastIndex(where: { $0.identifier?.hasPrefix("com.apple.") ?? false }) else {
            return "Path: " + path.map(pathText).joined(separator: " > ")
        }
        let own = path[(host + 1)...]
        // The last step is the element itself, whose identifier is on its head line already.
        guard own.dropLast().contains(where: { $0.identifier != nil || $0.dom != nil }) else { return nil }
        return "Path: " + own.map(pathText).joined(separator: " > ")
    }

    /// specs/source-hints.md R171: the element that holds a text node, which is what the markup names.
    static func insideLine(_ parent: DOMInfo.Parent, text: Bool = true) -> String {
        var named = parent.role
        if let id = parent.id { named += " · #\(id)" }
        if !parent.classes.isEmpty {
            named += " · ." + parent.classes.prefix(Self.classLimit).joined(separator: ".")
            if parent.classes.count > Self.classLimit { named += " (+\(parent.classes.count - Self.classLimit) more)" }
        }
        return "Inside: \(named) (\(text ? "a text node" : "this element") has no id or class of its own; these are its parent's)."
    }

    /// specs/source-hints.md R167. The count is of what is on screen, and a list that sorts or scrolls
    /// moves it; the line says so, so that an agent does not take it for the item's place in the data.
    static func positionLine(_ row: RowPosition) -> String {
        let direction = row.axis == .column ? "top to bottom" : "left to right"
        return "Position: \(row.index) of \(row.count) alike on screen, \(direction) (as drawn now; not the item's place in the data)."
    }

    /// specs/source-hints.md R160, with R164's other file and R165's catalog keys after it.
    static func sourceLine(_ hint: SourceHint, element: ResolvedElement) -> String {
        var line = foundLine(hint, element: element)
        if let around = hint.around {
            let at = around.place.lines.isEmpty ? around.place.file : around.place.file + ":" + around.place.lines.map(String.init).joined(separator: ", :")
            let named = around.strings.prefix(2).map { "\"\($0)\"" }.joined(separator: " and ")
            line += " Other text from this capture (\(named)) is in \(at), which may be what draws it."
        }
        for entry in (hint.localized ?? []).prefix(2) {
            line += " \"\(entry.key)\" is the key for \"\(entry.shown)\" in \(entry.table)."
        }
        return line
    }

    private static func foundLine(_ hint: SourceHint, element: ResolvedElement) -> String {
        func quoted(_ strings: [String]) -> String { strings.prefix(2).map { "\"\($0)\"" }.joined(separator: " and ") }
        let many = hint.strings.count > 1
        // A native string is a literal in the code; a page's id or class is a word inside one (R166).
        let web = element.dom != nil
        let named = web ? quoted(hint.strings) : (many ? "the strings " : "the string ") + quoted(hint.strings)
        let isIn = quoted(hint.strings) + (web ? (many ? " appear in" : " appears in") : many ? " are strings in" : " is a string in")
        // A stylesheet says how the class looks; when nothing else holds it, the markup builds the name at run time.
        let styled = web && !hint.places.isEmpty && hint.places.allSatisfy { $0.file.hasSuffix(".css") || $0.file.hasSuffix(".scss") }
            ? " Every place is a stylesheet: it styles the class, and the file that draws the element builds the name at run time." : ""
        func place(_ p: SourcePlace) -> String { p.lines.isEmpty ? p.file : p.file + ":" + p.lines.map(String.init).joined(separator: ", :") }
        let listed = hint.places.map(place)
        let more = hint.fileCount > hint.places.count ? " and \(hint.fileCount - hint.places.count) more" : ""
        if hint.together == true {
            // R172: a list of utility classes, found where it is written out on one line.
            let shown = hint.strings.prefix(3).map { "\"\($0)\"" }
            let rest = hint.strings.count - shown.count
            let classes = (shown.count > 1 ? shown.dropLast().joined(separator: ", ") + " and " + (shown.last ?? "") : shown.first ?? "")
                + (rest > 0 ? " and \(rest) more of its classes" : "")
            switch hint.kind {
            case .only:
                return "In source: \(listed.first ?? "") (the only file with \(classes) on one line)."
            case .likeliest:
                let others = listed.dropFirst().joined(separator: ", ")
                return "In source: \(classes) are on one line in \(hint.fileCount) files. Likeliest: \(listed.first ?? "") (it also has \(quoted(hint.alsoThere ?? [])) from this capture). Others: \(others)\(more)."
            default:
                return "In source: \(classes) are on one line in \(hint.fileCount) files, and nothing in this capture says which: \(listed.joined(separator: ", "))\(more). Use the image and the note to choose."
            }
        }
        switch hint.kind {
        case .only:
            return "In source: \(listed.first ?? "") (the only file in the project with \(named)).\(styled)"
        case .likeliest:
            let also = hint.alsoThere ?? []
            let why = also.isEmpty ? "it has more of this element's strings than the others"
                : "it also has \(quoted(also)) from this capture"
            let others = listed.dropFirst().joined(separator: ", ")
            return "In source: \(isIn) \(hint.fileCount) files. Likeliest: \(listed.first ?? "") (\(why)). Others: \(others)\(more).\(styled)"
        case .several:
            return "In source: \(isIn) \(hint.fileCount) files, and nothing in this capture says which: \(listed.joined(separator: ", "))\(more). Use the image and the note to choose.\(styled)"
        case .beside where element.dom != nil:
            // R166: a page's node found by its own words, its id and classes having led nowhere.
            return "In source: no id or rare class to go by; this element's own text \(quoted(hint.strings)) is at \(listed.joined(separator: ", "))."
        case .none where element.dom != nil:
            return "In source: no \(quoted(hint.strings)) in the project's files, so a search for \(hint.strings.count > 1 ? "them" : "it") will find nothing. The page may be built from other code than this folder holds now. If the image and the path do not settle where it is drawn, say so rather than guess."
        case .beside:
            let own = element.label != nil || element.identifier != nil
            let lead = own ? "In source: no string in the project matches this element's own text, so that text is probably data or the system's. Fixed text in or beside it: "
                : "In source: fixed text in or beside it: "
            return lead + "\(quoted(hint.strings)) at \(listed.joined(separator: ", "))."
        case .none:
            return "In source: no \(quoted(hint.strings)) string in the project, so a search for that text will find nothing. The text may be data, or the app on screen was built from other code than this folder holds now. If the image and the path do not settle where it is drawn, say so rather than guess."
        }
    }

    /// specs/web-source.md R150: what the page's framework said about the element, in the order Claude's Browser picker
    /// shows it. Source is the element's own JSX; Rendered at is where its component is used.
    static func componentLines(_ c: ComponentInfo) -> [String] {
        var lines: [String] = []
        let framework = c.framework == "react" ? "React" : c.framework
        if let name = c.name {
            var text = "Component: \(name)"
            if !c.ancestors.isEmpty {
                text += " in " + c.ancestors.prefix(Self.componentAncestorLimit).joined(separator: " › ")
                if c.ancestors.count > Self.componentAncestorLimit { text += " › …" }
            }
            lines.append(text + " (\(framework), read from the page)")
        }
        if !c.props.isEmpty {
            lines.append("Props: " + c.props.map { "\($0.name) \($0.value)" }.joined(separator: " · "))
        }
        if let source = c.source { lines.append("Source: \(source.text) (this element's JSX)") }
        if let rendered = c.renderedAt {
            lines.append("Rendered at: \(rendered.text)" + (c.name.map { " (where <\($0)> is used)" } ?? ""))
        }
        return lines
    }

    static let componentAncestorLimit = 4

    /// The line under an element with no handle: the fact in both modes. The advice to grep and add a handle
    /// only in fix mode, where the code on screen is the user's own; a reference capture is someone else's app,
    /// and the agent must not be told to edit it.
    private static func missingHandleLine(_ fact: String, mode: CaptureMode, fix advice: String) -> String {
        mode == .fix ? fact + " " + advice : fact
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

    /// R135: what a `LocantText` element is, under its head line, and how to find it.
    static let textLineNote = "Text read from the screen by Locant; not an accessibility element. The element it sits in is the next ⌥ level."
    static let textLineAdvice = "No identifier. Grep the label text; it is drawn by that element's view, the last step of Path before staticText."

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
