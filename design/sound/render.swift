import Accelerate
import Foundation
// Renders Locant's two interface sounds, `landed` and `missed` (specs/v0.8.1.md R60).
// A sound is a few decaying partials plus a touch of filtered noise for the mallet, under a 2 ms
// raised-cosine attack and a short fade at the end. Every number that shapes a set is below;
// change one, re-render, listen.
//
//   swiftc -O design/sound/render.swift -o design/sound/render
//   design/sound/render candidates <folder>   every set as WAV, for listening
//   design/sound/render ship <set>            one set as CAF into Locant/Feedback/Sounds (run from the repo root)

let rate = 48_000.0

/// One mode of the struck object: a multiple of the note's pitch, its level, and the time
/// constant of its exponential decay in seconds.
struct Partial { var ratio, gain, decay: Double }

/// A material: the modes a strike excites and the mallet's touch, a burst of noise in a band.
struct Material {
    var name: String
    var partials: [Partial]
    var touch, touchLow, touchHigh, touchDecay: Double
}

let sets = [
    // A small glass struck lightly: modes near 1 : 2.4 : 4.5, a twin of the fundamental two or
    // three hertz away, slow enough to shimmer rather than wobble, and a light tick for the touch.
    Material(name: "glass", partials: [
        Partial(ratio: 1.0, gain: 1.0, decay: 0.075),
        Partial(ratio: 1.0035, gain: 0.25, decay: 0.075),
        Partial(ratio: 2.43, gain: 0.30, decay: 0.045),
        Partial(ratio: 4.55, gain: 0.10, decay: 0.022),
    ], touch: 0.6, touchLow: 2_000, touchHigh: 5_000, touchDecay: 0.004),
    // A soft marimba bar: the fundamental and the bar's tuned fourth mode, a short wooden knock.
    Material(name: "wood", partials: [
        Partial(ratio: 1.0, gain: 1.0, decay: 0.055),
        Partial(ratio: 4.0, gain: 0.20, decay: 0.022),
    ], touch: 1.0, touchLow: 600, touchHigh: 2_500, touchDecay: 0.004),
    // A felt hammer on a string: harmonic partials stretched slightly, the upper ones soft and
    // short, a second string a hair sharp as in a piano's unison, a muffled thump.
    Material(name: "felt", partials: [
        Partial(ratio: 1.0, gain: 1.0, decay: 0.070),
        Partial(ratio: 1.0015, gain: 0.6, decay: 0.070),
        Partial(ratio: 2 * (1 + 0.0003 * 4).squareRoot(), gain: 0.40, decay: 0.045),
        Partial(ratio: 3 * (1 + 0.0003 * 9).squareRoot(), gain: 0.16, decay: 0.030),
        Partial(ratio: 4 * (1 + 0.0003 * 16).squareRoot(), gain: 0.07, decay: 0.022),
    ], touch: 0.8, touchLow: 500, touchHigh: 1_200, touchDecay: 0.005),
]

// The figure (R60): `landed` rises a fourth, onsets 70 ms apart, the second struck 2 dB softer;
// `missed` is one note a minor third below landed's first, its upper partials damped twice as
// fast, 3 dB quieter. Same pitches in every set, so a comparison hears the material only.
let landedPitches = (659.26, 880.00) // E5, A5
let missedPitch = 554.37 // C#5
let secondGain = pow(10, -2.0 / 20)
let secondOnset = 0.070
let landedLength = 0.250, missedLength = 0.250
let missedDamping = 2.0
let landedPeak = -18.0, missedPeak = -21.0 // dBFS
let attack = 0.002, fadeOut = 0.040

/// Deterministic noise, so a re-render is byte-identical.
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53) * 2 - 1
    }
}

/// RBJ cookbook low- and high-pass, Q 0.707.
struct Biquad {
    var b0, b1, b2, a1, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(cutoff: Double, lowPass: Bool) {
        let w = 2 * Double.pi * cutoff / rate, c = cos(w), alpha = sin(w) / (2 * 0.7071)
        let a0 = 1 + alpha
        let edge = lowPass ? (1 - c) / 2 : (1 + c) / 2
        b0 = edge / a0
        b1 = (lowPass ? 1 - c : -(1 + c)) / a0
        b2 = edge / a0
        a1 = -2 * c / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

/// One strike of `material` at `pitch`, added into `buffer` from `onset` seconds. `damping`
/// shortens every partial above the fundamental's family.
func strike(_ material: Material, pitch: Double, gain: Double, onset: Double, damping: Double, seed: UInt64, into buffer: inout [Double]) {
    let start = Int((onset * rate).rounded())
    var noise = SplitMix64(state: seed)
    var high = Biquad(cutoff: material.touchLow, lowPass: false)
    var low = Biquad(cutoff: material.touchHigh, lowPass: true)
    for i in start..<buffer.count {
        let t = Double(i - start) / rate
        var sample = 0.0
        for partial in material.partials {
            let decay = partial.ratio < 1.5 ? partial.decay : partial.decay / damping
            sample += partial.gain * exp(-t / decay) * sin(2 * .pi * pitch * partial.ratio * t)
        }
        sample += material.touch * low.process(high.process(noise.next())) * exp(-t / material.touchDecay)
        let rise = t < attack ? 0.5 - 0.5 * cos(.pi * t / attack) : 1
        buffer[i] += gain * rise * sample
    }
}

func render(_ material: Material, landed: Bool) -> [Float] {
    var buffer = [Double](repeating: 0, count: Int(((landed ? landedLength : missedLength) * rate).rounded()))
    if landed {
        strike(material, pitch: landedPitches.0, gain: 1, onset: 0, damping: 1, seed: 1, into: &buffer)
        strike(material, pitch: landedPitches.1, gain: secondGain, onset: secondOnset, damping: 1, seed: 2, into: &buffer)
    } else {
        strike(material, pitch: missedPitch, gain: 1, onset: 0, damping: missedDamping, seed: 3, into: &buffer)
    }
    // The tail fades to exactly zero, so the file ends without a click.
    let fadeStart = buffer.count - Int((fadeOut * rate).rounded())
    for i in fadeStart..<buffer.count {
        buffer[i] *= 0.5 + 0.5 * cos(.pi * Double(i - fadeStart) / Double(buffer.count - 1 - fadeStart))
    }
    let peak = buffer.map(abs).max()!
    let target = pow(10, (landed ? landedPeak : missedPeak) / 20)
    return buffer.map { Float($0 / peak * target) }
}

/// Mono 48 kHz 24-bit PCM.
func wav(_ samples: [Float]) -> Data {
    var data = Data()
    func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
    func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    let bytes = UInt32(samples.count * 3)
    append("RIFF"); append32(36 + bytes); append("WAVE")
    append("fmt "); append32(16); append16(1); append16(1); append32(48_000); append32(48_000 * 3); append16(3); append16(24)
    append("data"); append32(bytes)
    for sample in samples {
        let value = Int32((Double(max(-1, min(1, sample))) * 8_388_607).rounded())
        data.append(contentsOf: [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value >> 16)])
    }
    return data
}

/// Share of the energy between `low` and `high` hertz.
func bandShare(_ samples: [Float], low: Double, high: Double) -> Double {
    let n = 16_384
    var real = [Float](repeating: 0, count: n)
    for (i, sample) in samples.prefix(n).enumerated() { real[i] = sample }
    let dft = try! vDSP.DiscreteFourierTransform(count: n, direction: .forward, transformType: .complexComplex, ofType: Float.self)
    var outReal = [Float](repeating: 0, count: n), outImaginary = [Float](repeating: 0, count: n)
    dft.transform(inputReal: real, inputImaginary: [Float](repeating: 0, count: n), outputReal: &outReal, outputImaginary: &outImaginary)
    var inBand = 0.0, total = 0.0
    for k in 1..<(n / 2) {
        let power = Double(outReal[k] * outReal[k] + outImaginary[k] * outImaginary[k])
        let frequency = Double(k) * rate / Double(n)
        total += power
        if frequency >= low, frequency <= high { inBand += power }
    }
    return inBand / total
}

func report(_ name: String, _ samples: [Float]) {
    let peak = 20 * log10(Double(samples.map(abs).max()!))
    let rms = 20 * log10((samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot())
    let band = bandShare(samples, low: 500, high: 5_000) * 100
    print(String(format: "%-14@ %4.0f ms   peak %6.1f dBFS   rms %6.1f dBFS   500 Hz–5 kHz %5.1f %%", name as NSString, Double(samples.count) / rate * 1000, peak, rms, band))
}

let arguments = CommandLine.arguments
switch (arguments.count > 1 ? arguments[1] : "", arguments.count > 2 ? arguments[2] : "") {
case ("candidates", let folder) where !folder.isEmpty:
    let directory = URL(filePath: folder, directoryHint: .isDirectory)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for material in sets {
        for landed in [true, false] {
            let name = "\(material.name)-\(landed ? "landed" : "missed")"
            let samples = render(material, landed: landed)
            try! wav(samples).write(to: directory.appending(path: "\(name).wav"))
            report(name, samples)
        }
    }
case ("ship", let name) where sets.contains { $0.name == name }:
    let material = sets.first { $0.name == name }!
    let sounds = URL(filePath: "Locant/Feedback/Sounds", directoryHint: .isDirectory)
    try! FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)
    for landed in [true, false] {
        let sound = landed ? "landed" : "missed"
        let samples = render(material, landed: landed)
        let temporary = FileManager.default.temporaryDirectory.appending(path: "locant-\(sound).wav")
        try! wav(samples).write(to: temporary)
        let convert = Process()
        convert.executableURL = URL(filePath: "/usr/bin/afconvert")
        convert.arguments = ["-f", "caff", "-d", "LEI24", "-c", "1", temporary.path, sounds.appending(path: "\(sound).caf").path]
        try! convert.run()
        convert.waitUntilExit()
        precondition(convert.terminationStatus == 0, "afconvert failed for \(sound)")
        report("\(name) \(sound)", samples)
    }
default:
    print("usage: render candidates <folder> | render ship <\(sets.map(\.name).joined(separator: "|"))>")
    exit(64)
}
