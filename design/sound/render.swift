import Accelerate
import Foundation
// Renders Locant's two interface sounds, `landed` and `missed` (specs/v0.8.1.md R60).
// A sound is one strike of a wooden bar: the mallet's contact (filtered noise) and the bar's modes
// decaying under it, with a 2 ms raised-cosine attack and a short fade at the end. One strike, no
// melody: two notes a fixed interval apart read as a device connecting, not as a capture landing.
// `missed` is the same object struck lower and damped, so it reads as nothing landing.
// Every number that shapes a set is below; change one, re-render, listen.
//
//   swiftc -O design/sound/render.swift -o design/sound/render
//   design/sound/render candidates <folder>   every set as WAV, for listening
//   design/sound/render ship <set>            one set as CAF into Locant/Feedback/Sounds (run from the repo root)

let rate = 48_000.0

/// One mode of the struck object: a multiple of the strike's pitch, its level, and the time
/// constant of its exponential decay in seconds.
struct Partial { var ratio, gain, decay: Double }

/// One strike: when it lands, its pitch and level, and how much harder its upper modes are damped.
struct Strike { var pitch, gain, onset, damping: Double }

/// A set: the modes a strike excites, the mallet's contact, and the two sounds made from it.
struct Material {
    var name: String
    var partials: [Partial]
    var touch, touchLow, touchHigh, touchDecay: Double
    var landed, missed: [Strike]
    var landedLength, missedLength: Double
}

// The same pitches in every set, so a comparison hears the object and not the note: G5 for
// `landed`, C5 a fifth below for `missed`, both well inside the 500 Hz to 5 kHz band.
let landedPitch = 783.99, missedPitch = 523.25
let missedDamping = 2.0

let sets = [
    // A soft marimba bar under a felt mallet: the tuned fourth mode flashes, the fundamental sings
    // briefly. The most tonal of the four.
    Material(name: "tap", partials: [
        Partial(ratio: 1.0, gain: 1.0, decay: 0.055),
        Partial(ratio: 4.0, gain: 0.20, decay: 0.022),
    ], touch: 1.0, touchLow: 600, touchHigh: 2_500, touchDecay: 0.004,
       landed: [Strike(pitch: landedPitch, gain: 1, onset: 0, damping: 1)],
       missed: [Strike(pitch: missedPitch, gain: 1, onset: 0, damping: missedDamping)],
       landedLength: 0.200, missedLength: 0.200),
    // Mostly the mallet: a short wooden knock with just enough pitch to place it. The most
    // physical of the four, and the shortest.
    Material(name: "knock", partials: [
        Partial(ratio: 1.0, gain: 0.45, decay: 0.028),
        Partial(ratio: 4.0, gain: 0.10, decay: 0.012),
    ], touch: 2.4, touchLow: 500, touchHigh: 3_000, touchDecay: 0.005,
       landed: [Strike(pitch: landedPitch, gain: 1, onset: 0, damping: 1)],
       missed: [Strike(pitch: missedPitch, gain: 1, onset: 0, damping: missedDamping)],
       landedLength: 0.130, missedLength: 0.130),
    // Something set down on a wooden surface: the same contact, then a longer, softer body under it.
    Material(name: "place", partials: [
        Partial(ratio: 1.0, gain: 1.0, decay: 0.085),
        Partial(ratio: 4.0, gain: 0.12, decay: 0.018),
    ], touch: 1.2, touchLow: 500, touchHigh: 2_200, touchDecay: 0.0045,
       landed: [Strike(pitch: landedPitch, gain: 1, onset: 0, damping: 1)],
       missed: [Strike(pitch: missedPitch, gain: 1, onset: 0, damping: missedDamping)],
       landedLength: 0.250, missedLength: 0.220),
    // Two strikes of the same bar, 45 ms apart, the second 4 dB softer: a "tok-tok" that confirms
    // without ever becoming an interval. `missed` stays one strike, so the two never trade places.
    Material(name: "double", partials: [
        Partial(ratio: 1.0, gain: 1.0, decay: 0.045),
        Partial(ratio: 4.0, gain: 0.20, decay: 0.020),
    ], touch: 1.0, touchLow: 600, touchHigh: 2_500, touchDecay: 0.004,
       landed: [Strike(pitch: landedPitch, gain: 1, onset: 0, damping: 1),
                Strike(pitch: landedPitch, gain: pow(10, -4.0 / 20), onset: 0.045, damping: 1)],
       missed: [Strike(pitch: missedPitch, gain: 1, onset: 0, damping: missedDamping)],
       landedLength: 0.220, missedLength: 0.180),
]

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

/// One strike of `material`, added into `buffer` from its onset.
func play(_ strike: Strike, of material: Material, seed: UInt64, into buffer: inout [Double]) {
    let start = Int((strike.onset * rate).rounded())
    var noise = SplitMix64(state: seed)
    var high = Biquad(cutoff: material.touchLow, lowPass: false)
    var low = Biquad(cutoff: material.touchHigh, lowPass: true)
    for i in start..<buffer.count {
        let t = Double(i - start) / rate
        var sample = 0.0
        for partial in material.partials {
            let decay = partial.ratio < 1.5 ? partial.decay : partial.decay / strike.damping
            sample += partial.gain * exp(-t / decay) * sin(2 * .pi * strike.pitch * partial.ratio * t)
        }
        sample += material.touch * low.process(high.process(noise.next())) * exp(-t / material.touchDecay)
        let rise = t < attack ? 0.5 - 0.5 * cos(.pi * t / attack) : 1
        buffer[i] += strike.gain * rise * sample
    }
}

func render(_ material: Material, landed: Bool) -> [Float] {
    let length = landed ? material.landedLength : material.missedLength
    var buffer = [Double](repeating: 0, count: Int((length * rate).rounded()))
    for (index, strike) in (landed ? material.landed : material.missed).enumerated() {
        play(strike, of: material, seed: UInt64(index + 1), into: &buffer)
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
