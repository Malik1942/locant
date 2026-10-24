import CoreGraphics
import Foundation

/// specs/capture-shapes.md R118: a screen sample as `ShapeFinder` reads it. RGBA, 8 bits per channel,
/// top row first, `scale` samples per point; `frame` is the area it shows, in global CG points.
struct PixelGrid: Sendable {
    let frame: CGRect
    let scale: CGFloat
    let width: Int
    let height: Int
    let bytes: [UInt8]
    /// Rises with every new sample, so nothing read from an older one is reused (R119).
    let generation: Int
    /// R119: the edge samples, mapped once here so hover never pays for them.
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

    /// R119: a sample is an edge when one of its four neighbors differs from it by more than `tolerance`.
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

    /// The sample under a global point; nil off the grid.
    func sample(at point: CGPoint) -> (x: Int, y: Int)? {
        let x = Int(((point.x - frame.minX) * scale).rounded(.down))
        let y = Int(((point.y - frame.minY) * scale).rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return (x, y)
    }

    /// The samples a global rectangle covers, unclipped: they may lie off the grid.
    func span(of rect: CGRect) -> SampleBox {
        SampleBox(minX: Int(((rect.minX - frame.minX) * scale).rounded(.down)),
                  minY: Int(((rect.minY - frame.minY) * scale).rounded(.down)),
                  maxX: Int(((rect.maxX - frame.minX) * scale).rounded(.up)) - 1,
                  maxY: Int(((rect.maxY - frame.minY) * scale).rounded(.up)) - 1)
    }

    /// `span(of:)` clipped to the grid; nil when nothing is left.
    func box(of rect: CGRect) -> SampleBox? {
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

    /// R119: the largest of the three channel differences, on a 0–255 scale.
    func difference(_ other: RGB) -> Int {
        max(abs(Int(r) - Int(other.r)), abs(Int(g) - Int(other.g)), abs(Int(b) - Int(other.b)))
    }
}

/// specs/capture-shapes.md R119: the shape the pixels show at a point or around a rectangle: edges first,
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
    /// them (R119), and the shape when R119 accepted it.
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

    /// The fill from the 5×5 pt patch around `point`; its `shape` is nil when R119 rejects it. Nil when
    /// the point lies outside the bound or the grid.
    static func fill(at point: CGPoint, in grid: PixelGrid, bound: CGRect) -> Fill? {
        guard let box = grid.box(of: bound), let center = grid.sample(at: point),
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
        guard let box = grid.box(of: bound) else { return nil }
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

    /// R119's "most common color": counted with each channel's three low bits dropped; the mean of the
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

    /// R119's tests: not the background (within `edgeSlack` of two opposite sides of the bound), under
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

    /// The samples on the outline of `rect` that lie inside `box`.
    private static func ringSamples(around rect: CGRect, in grid: PixelGrid, box: SampleBox) -> [(x: Int, y: Int)] {
        let r = grid.span(of: rect)
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

/// specs/capture-shapes.md R117: what the ladder asks of the pixels. `ShapeLookup` answers from a screen
/// sample; tests answer from fixed rectangles.
protocol ShapeSource {
    /// R119: the shape at a point; nil when there is none.
    mutating func shape(at point: CGPoint) -> CGRect?
    /// R119: the shapes around a rectangle, innermost first, at most three.
    mutating func shapes(around rect: CGRect) -> [CGRect]
}

/// The live `ShapeSource` over one screen sample. `memo` carries the last fill and the shapes found around
/// rectangles from one hover step to the next while the sample and the bound stay the same (R119).
struct ShapeLookup: ShapeSource, Sendable {
    struct Memo: Sendable {
        var generation = -1
        var bound = CGRect.null
        var lastFill: ShapeFinder.Fill?
        var around: [Frame: [CGRect]] = [:]
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
}
