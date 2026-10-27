import CoreGraphics
import Foundation

/// specs/capture-shapes.md R126: a screen sample as `ShapeFinder` reads it. RGBA, 8 bits per channel,
/// top row first, `scale` samples per point; `frame` is the area it shows, in global CG points.
struct PixelGrid: Sendable {
    let frame: CGRect
    let scale: CGFloat
    let width: Int
    let height: Int
    let bytes: [UInt8]
    /// Rises with every new sample, so nothing read from an older one is reused (R127).
    let generation: Int
    /// R127: the edge samples, mapped once here so hover never pays for them.
    let edges: [Bool]

    init(frame: CGRect, scale: CGFloat, width: Int, height: Int, bytes: [UInt8], generation: Int) {
        precondition(bytes.count == width * height * 4, "four bytes a sample")
        self.frame = frame
        self.scale = scale
        self.width = width
        self.height = height
        self.bytes = bytes
        self.generation = generation
        self.edges = Self.edgeMap(bytes, width: width, height: height, tolerance: ShapeFinder.edgeTolerance)
    }

    /// R127: a sample is an edge when one of its four neighbors differs from it by more than `tolerance`.
    /// A thin rim between two equal fills is an edge on both sides; a gradient of a level or two is not.
    static func edgeMap(_ bytes: [UInt8], width: Int, height: Int, tolerance: Int) -> [Bool] {
        var edges = [Bool](repeating: false, count: width * height)
        bytes.withUnsafeBufferPointer { px in
            edges.withUnsafeMutableBufferPointer { e in
                for y in 0..<height {
                    for x in 0..<width {
                        let i = (y * width + x) * 4
                        let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                        func far(_ j: Int) -> Bool {
                            max(abs(Int(px[j]) - r), abs(Int(px[j + 1]) - g), abs(Int(px[j + 2]) - b)) > tolerance
                        }
                        if (x > 0 && far(i - 4)) || (x < width - 1 && far(i + 4))
                            || (y > 0 && far(i - width * 4)) || (y < height - 1 && far(i + width * 4)) {
                            e[y * width + x] = true
                        }
                    }
                }
            }
        }
        return edges
    }

    /// The image drawn into an RGBA buffer of its own size. The one conversion for the live sample and
    /// the test fixtures, so both are read the same way.
    init?(image: CGImage, frame: CGRect, scale: CGFloat, generation: Int) {
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(frame: frame, scale: scale, width: width, height: height, bytes: bytes, generation: generation)
    }

    func color(x: Int, y: Int) -> RGB {
        let i = (y * width + x) * 4
        return RGB(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2])
    }

    /// The sample under a global point; nil off the grid, and for a point that is not finite. Compared
    /// before converting, since a point can come from another app's accessibility frame.
    func sample(at point: CGPoint) -> (x: Int, y: Int)? {
        let x = ((point.x - frame.minX) * scale).rounded(.down)
        let y = ((point.y - frame.minY) * scale).rounded(.down)
        guard x >= 0, y >= 0, x < CGFloat(width), y < CGFloat(height) else { return nil } // NaN fails too
        return (Int(x), Int(y))
    }

    /// The samples a global rectangle covers, unclipped up to 2 samples beyond the grid. An accessibility
    /// frame can be huge, infinite, or NaN: each edge is clamped before it is converted, and a rectangle
    /// that is not finite covers nothing.
    func span(of rect: CGRect) -> SampleBox {
        guard rect.isFinite else { return SampleBox(minX: 0, minY: 0, maxX: -1, maxY: -1) }
        func index(_ points: CGFloat, from origin: CGFloat, _ rule: FloatingPointRoundingRule, count: Int) -> Int {
            let value = ((points - origin) * scale).rounded(rule)
            guard value > -2 else { return -2 } // NaN lands here too
            return value < CGFloat(count + 2) ? Int(value) : count + 2
        }
        return SampleBox(minX: index(rect.minX, from: frame.minX, .down, count: width),
                         minY: index(rect.minY, from: frame.minY, .down, count: height),
                         maxX: index(rect.maxX, from: frame.minX, .up, count: width) - 1,
                         maxY: index(rect.maxY, from: frame.minY, .up, count: height) - 1)
    }

    /// `span(of:)` clipped to the grid; nil when nothing is left, or when `rect` is not finite.
    func box(of rect: CGRect) -> SampleBox? {
        guard rect.isFinite else { return nil }
        let raw = span(of: rect)
        let clipped = SampleBox(minX: max(raw.minX, 0), minY: max(raw.minY, 0),
                                maxX: min(raw.maxX, width - 1), maxY: min(raw.maxY, height - 1))
        return clipped.minX <= clipped.maxX && clipped.minY <= clipped.maxY ? clipped : nil
    }

    /// Samples back in global points.
    func rect(of box: SampleBox) -> CGRect {
        CGRect(x: frame.minX + CGFloat(box.minX) / scale, y: frame.minY + CGFloat(box.minY) / scale,
               width: CGFloat(box.width) / scale, height: CGFloat(box.height) / scale)
    }

    /// specs/capture-shapes.md R134: the bounds, in global points, of the edge samples among those `rect`
    /// covers (`box(of:)`): what is drawn inside it. A step marks the sample on each side, so a drawn edge's
    /// bounds reach one sample past it. Nil when no edge is there, and when `rect` is not finite or off the grid.
    func edgeBounds(inside rect: CGRect) -> CGRect? {
        guard let box = box(of: rect) else { return nil }
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        edges.withUnsafeBufferPointer { edge in
            for y in box.minY...box.maxY {
                let row = y * width
                for x in box.minX...box.maxX where edge[row + x] {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard minX <= maxX else { return nil }
        return self.rect(of: SampleBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY))
    }

    /// specs/capture-shapes.md R135: the samples `rect` covers (`box(of:)`) as an image, the same sRGB RGBA bytes
    /// copied once, row by row, and the rectangle they show in global points. Nil when `rect` is not finite or off
    /// the grid.
    func image(of rect: CGRect) -> (image: CGImage, frame: CGRect)? {
        guard let box = box(of: rect), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let data = CFDataCreateMutable(nil, box.width * 4 * box.height) else { return nil }
        forEachRow(of: box) { row in
            CFDataAppendBytes(data, row.baseAddress!.assumingMemoryBound(to: UInt8.self), row.count)
        }
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(width: box.width, height: box.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: box.width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return (image, self.rect(of: box))
    }

    /// R135: the bytes of each row of `box`, a box inside the grid (`box(of:)`), top to bottom.
    func forEachRow(of box: SampleBox, _ body: (UnsafeRawBufferPointer) -> Void) {
        bytes.withUnsafeBytes { raw in
            for y in box.minY...box.maxY {
                let start = (y * width + box.minX) * 4
                body(UnsafeRawBufferPointer(rebasing: raw[start..<(start + box.width * 4)]))
            }
        }
    }
}

fileprivate extension CGRect {
    /// Not null, not `CGRect.infinite`, and every edge a finite number: what the pixel code can convert.
    var isFinite: Bool {
        !isNull && !isInfinite && origin.x.isFinite && origin.y.isFinite && size.width.isFinite && size.height.isFinite
    }
}

/// Inclusive sample bounds.
struct SampleBox: Equatable, Sendable {
    var minX: Int, minY: Int, maxX: Int, maxY: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }

    func contains(x: Int, y: Int) -> Bool { x >= minX && x <= maxX && y >= minY && y <= maxY }
}

struct RGB: Equatable, Sendable {
    var r: UInt8, g: UInt8, b: UInt8

    /// R127: the largest of the three channel differences, on a 0–255 scale.
    func difference(_ other: RGB) -> Int {
        max(abs(Int(r) - Int(other.r)), abs(Int(g) - Int(other.g)), abs(Int(b) - Int(other.b)))
    }
}

/// specs/capture-shapes.md R127: the shape the pixels show at a point or around a rectangle: edges first,
/// then a fill through what is not an edge. Pure.
enum ShapeFinder {
    /// A sample is an edge when a neighbor differs from it by more than this; seeds are within it of the
    /// seed color. Set by the real-screen fixtures on Oct 23 (6 leaked out of every glass shape).
    static let edgeTolerance = 4
    /// The largest difference from the seed color a fill takes: stops a drift through a gap in an edge.
    static let seedTolerance = 24
    /// Points: the patch around the pointer, and the ring's distance outside a rectangle.
    static let patchSide: CGFloat = 5
    static let ringOffset: CGFloat = 2
    /// Points: the smallest shape, and how much larger than a rectangle the shape around it must be.
    static let minSide: CGFloat = 12
    static let minGrowth: CGFloat = 2
    /// Points: a fill this close to two opposite sides of the bound is the background.
    static let edgeSlack: CGFloat = 1
    static let maxAreaFraction = 0.6
    static let enclosingLevels = 3

    /// One fill from the pointer: the samples it took, so its answer stands while the pointer stays on
    /// them (R127), and the shape when R127 accepted it.
    struct Fill: Sendable {
        let generation: Int
        let box: SampleBox
        let taken: [Bool]
        let shape: CGRect?

        func covers(_ point: CGPoint, in grid: PixelGrid) -> Bool {
            guard grid.generation == generation, let s = grid.sample(at: point), box.contains(x: s.x, y: s.y) else { return false }
            return taken[(s.y - box.minY) * box.width + (s.x - box.minX)]
        }
    }

    /// The fill from the 5×5 pt patch around `point`; its `shape` is nil when R127 rejects it. Nil when
    /// the point lies outside the bound or the grid, and when the bound is empty or not finite.
    static func fill(at point: CGPoint, in grid: PixelGrid, bound: CGRect) -> Fill? {
        guard !bound.isEmpty, let box = grid.box(of: bound), let center = grid.sample(at: point),
              box.contains(x: center.x, y: center.y) else { return nil }
        let half = Int((patchSide * grid.scale / 2).rounded(.down))
        var patch: [(x: Int, y: Int)] = []
        for y in (center.y - half)...(center.y + half) {
            for x in (center.x - half)...(center.x + half) where box.contains(x: x, y: y) {
                patch.append((x, y))
            }
        }
        guard let seed = seedColor(of: patch.map { grid.color(x: $0.x, y: $0.y) }) else { return nil }
        let seeds = patch.filter { grid.color(x: $0.x, y: $0.y).difference(seed) <= edgeTolerance }
        let grown = grow(from: seeds, seed: seed, in: grid, box: box)
        var shape = grown.extent.flatMap { accept($0, in: box, grid: grid) }
        if let found = shape, !found.contains(point) { shape = nil }
        return Fill(generation: grid.generation, box: box, taken: grown.taken, shape: shape)
    }

    /// The shape around `rect`: the fill from the ring 2 pt outside it, accepted only if it holds `rect`
    /// and is at least 2 pt larger on one side, so an element's own background is not its shape.
    static func shape(around rect: CGRect, in grid: PixelGrid, bound: CGRect) -> CGRect? {
        guard !bound.isEmpty, let box = grid.box(of: bound) else { return nil }
        let ring = ringSamples(around: rect.insetBy(dx: -ringOffset, dy: -ringOffset), in: grid, box: box)
        guard let seed = seedColor(of: ring.map { grid.color(x: $0.x, y: $0.y) }) else { return nil }
        let seeds = ring.filter { grid.color(x: $0.x, y: $0.y).difference(seed) <= edgeTolerance }
        guard let extent = grow(from: seeds, seed: seed, in: grid, box: box).extent,
              let shape = accept(extent, in: box, grid: grid),
              shape.insetBy(dx: -edgeSlack, dy: -edgeSlack).contains(rect) else { return nil }
        let growth = max(rect.minX - shape.minX, shape.maxX - rect.maxX, rect.minY - shape.minY, shape.maxY - rect.maxY)
        return growth >= minGrowth ? shape : nil
    }

    /// The shapes around `rect`, innermost first: each found around the one before, up to three,
    /// stopping at the first that finds nothing.
    static func enclosing(_ rect: CGRect, in grid: PixelGrid, bound: CGRect) -> [CGRect] {
        var found: [CGRect] = []
        var current = rect
        while found.count < enclosingLevels, let next = shape(around: current, in: grid, bound: bound) {
            found.append(next)
            current = next
        }
        return found
    }

    /// R127's "most common color": counted with each channel's three low bits dropped; the mean of the
    /// largest bucket, the lower bucket on a tie.
    static func seedColor(of colors: [RGB]) -> RGB? {
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for c in colors {
            let key = Int(c.r >> 3) << 10 | Int(c.g >> 3) << 5 | Int(c.b >> 3)
            var bucket = buckets[key] ?? (0, 0, 0, 0)
            bucket.count += 1
            bucket.r += Int(c.r)
            bucket.g += Int(c.g)
            bucket.b += Int(c.b)
            buckets[key] = bucket
        }
        guard let best = buckets.max(by: { a, b in
            a.value.count < b.value.count || (a.value.count == b.value.count && a.key > b.key)
        }) else { return nil }
        let n = best.value.count
        return RGB(r: UInt8(best.value.r / n), g: UInt8(best.value.g / n), b: UInt8(best.value.b / n))
    }

    // MARK: Growing

    private struct Growth {
        var taken: [Bool]
        /// Nil when nothing was taken, or when the fill reached two opposite sides of the bound or passed
        /// `maxAreaFraction` of it, and stopped: the background.
        var extent: SampleBox?
    }

    private static let steps = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    /// The 4-connected fill from `seeds` inside `box`: a neighbor joins when it is not an edge sample
    /// (`PixelGrid.edges`) and is within `seedTolerance` of the seed color.
    private static func grow(from seeds: [(x: Int, y: Int)], seed: RGB, in grid: PixelGrid, box: SampleBox) -> Growth {
        let bw = box.width, bh = box.height
        var taken = [Bool](repeating: false, count: bw * bh)
        guard !seeds.isEmpty else { return Growth(taken: taken, extent: nil) }
        let limit = Int(maxAreaFraction * Double(bw * bh))
        let slack = Int((edgeSlack * grid.scale).rounded())
        let gw = grid.width, ox = box.minX, oy = box.minY
        let sr = Int(seed.r), sg = Int(seed.g), sb = Int(seed.b)
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        var count = 0
        var overflow = false
        var stack: [Int] = []
        stack.reserveCapacity(4096)
        grid.bytes.withUnsafeBufferPointer { px in
            grid.edges.withUnsafeBufferPointer { edge in
                taken.withUnsafeMutableBufferPointer { took in
                    func take(_ local: Int) {
                        took[local] = true
                        count += 1
                        let x = local % bw, y = local / bw
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                        stack.append(local)
                    }
                    for s in seeds {
                        let local = (s.y - oy) * bw + (s.x - ox)
                        if !took[local] { take(local) }
                    }
                    while let current = stack.popLast() {
                        // The background: past the area limit, or across the bound from side to side.
                        if count > limit || (minX <= slack && maxX >= bw - 1 - slack) || (minY <= slack && maxY >= bh - 1 - slack) {
                            overflow = true
                            return
                        }
                        let x = current % bw, y = current / bw
                        for (dx, dy) in steps {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < bw, ny < bh else { continue }
                            let next = ny * bw + nx
                            let at = (oy + ny) * gw + ox + nx
                            guard !took[next], !edge[at] else { continue }
                            let r = Int(px[at * 4]), g = Int(px[at * 4 + 1]), b = Int(px[at * 4 + 2])
                            guard max(abs(r - sr), abs(g - sg), abs(b - sb)) <= seedTolerance else { continue }
                            take(next)
                        }
                    }
                }
            }
        }
        guard !overflow, count > 0 else { return Growth(taken: taken, extent: nil) }
        return Growth(taken: taken, extent: SampleBox(minX: ox + minX, minY: oy + minY, maxX: ox + maxX, maxY: oy + maxY))
    }

    /// R127's tests: not the background (within `edgeSlack` of two opposite sides of the bound), under
    /// `maxAreaFraction` of it, at least `minSide` either way.
    private static func accept(_ extent: SampleBox, in box: SampleBox, grid: PixelGrid) -> CGRect? {
        let slack = Int((edgeSlack * grid.scale).rounded())
        let left = extent.minX - box.minX <= slack, right = box.maxX - extent.maxX <= slack
        let top = extent.minY - box.minY <= slack, bottom = box.maxY - extent.maxY <= slack
        guard !(left && right), !(top && bottom) else { return nil }
        let shape = grid.rect(of: extent), bound = grid.rect(of: box)
        guard shape.width * shape.height < maxAreaFraction * bound.width * bound.height,
              shape.width >= minSide, shape.height >= minSide else { return nil }
        return shape
    }

    /// The samples on the outline of `rect` that lie inside `box`. The outline is cut to the grid grown by
    /// 2 samples first, so a frame thousands of points tall builds only the part the sample shows.
    private static func ringSamples(around rect: CGRect, in grid: PixelGrid, box: SampleBox) -> [(x: Int, y: Int)] {
        let margin = 2 / grid.scale
        let visible = rect.intersection(grid.frame.insetBy(dx: -margin, dy: -margin))
        guard visible.isFinite else { return [] }
        let r = grid.span(of: visible)
        var ring: [(x: Int, y: Int)] = []
        for x in stride(from: r.minX, through: r.maxX, by: 1) {
            ring.append((x, r.minY))
            ring.append((x, r.maxY))
        }
        for y in stride(from: r.minY + 1, to: r.maxY, by: 1) {
            ring.append((r.minX, y))
            ring.append((r.maxX, y))
        }
        return ring.filter { box.contains(x: $0.x, y: $0.y) }
    }
}

/// specs/capture-shapes.md R125: what the ladder asks of the pixels. `ShapeLookup` answers from a screen
/// sample; tests answer from fixed rectangles.
protocol ShapeSource {
    /// R127: the shape at a point; nil when there is none.
    mutating func shape(at point: CGPoint) -> CGRect?
    /// R127: the shapes around a rectangle, innermost first, at most three.
    mutating func shapes(around rect: CGRect) -> [CGRect]
    /// R134: the bounds of what is drawn inside a rectangle (its edge samples); nil when nothing is.
    mutating func ink(inside rect: CGRect) -> CGRect?
}

/// The live `ShapeSource` over one screen sample. `memo` carries the last fill, the shapes found around
/// rectangles, and what is drawn inside them (R134) from one hover step to the next while the sample and the
/// bound stay the same (R127).
struct ShapeLookup: ShapeSource, Sendable {
    struct Memo: Sendable {
        var generation = -1
        var bound = CGRect.null
        var lastFill: ShapeFinder.Fill?
        var around: [Frame: [CGRect]] = [:]
        var ink: [Frame: CGRect?] = [:]
    }

    let grid: PixelGrid
    let bound: CGRect
    private(set) var memo: Memo

    init(grid: PixelGrid, bound: CGRect, memo: Memo) {
        self.grid = grid
        self.bound = bound
        self.memo = memo.generation == grid.generation && memo.bound == bound ? memo : Memo(generation: grid.generation, bound: bound)
    }

    mutating func shape(at point: CGPoint) -> CGRect? {
        if let fill = memo.lastFill, fill.covers(point, in: grid) { return fill.shape }
        let fill = ShapeFinder.fill(at: point, in: grid, bound: bound)
        memo.lastFill = fill
        return fill?.shape
    }

    mutating func shapes(around rect: CGRect) -> [CGRect] {
        let key = Frame(rect)
        if let known = memo.around[key] { return known }
        let found = ShapeFinder.enclosing(rect, in: grid, bound: bound)
        if memo.around.count >= 64 { memo.around.removeAll() }
        memo.around[key] = found
        return found
    }

    mutating func ink(inside rect: CGRect) -> CGRect? {
        let key = Frame(rect)
        if let known = memo.ink[key] { return known }
        let found = grid.edgeBounds(inside: rect)
        if memo.ink.count >= 64 { memo.ink.removeAll() }
        memo.ink.updateValue(found, forKey: key) // a nil answer is kept too
        return found
    }
}
