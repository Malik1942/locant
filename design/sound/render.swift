import Accelerate
import Foundation
// Renders Locant's two interface sounds, `landed` and `missed` (specs/v0.8.1.md R60).
// A sound is one strike of a bar: the mallet's contact (filtered noise) and the bar's modes
// decaying under it, under a raised-cosine attack, with the ring allowed to finish before the fade.
// One strike, no melody: two notes a fixed interval apart read as a device connecting, not as a
// capture landing. `missed` is the same bar struck a fifth lower and damped, so nothing lands.
//
// The numbers come from measuring macOS's own interface sounds (45 files, Sep 20 2026). What that
// corpus says, and this file follows: confirmations sit at 290 to 740 Hz (macOS's own screenshot
// sound is 392 Hz, the pitch of `landed` here); they last 420 to 755 ms and always end quieter
// than -46 dB below peak, so the file is longer than the ring, never shorter; they carry a second
// mode within about 25 dB of the fundamental, because a lone sine reads as a test tone; they peak
// around -15 dBFS, well under an alert; and above 4 kHz they hold essentially nothing.
// Every number that shapes a set is below; change one, re-render, listen.
//
//   swiftc -O design/sound/render.swift -o design/sound/render
//   design/sound/render candidates <folder>   every set as WAV, for listening
//   design/sound/render ship <set>            one set as CAF into Locant/Feedback/Sounds (run from the repo root)

let rate = 48_000.0

/// One mode of the struck object: a multiple of the strike's pitch, its level, and the time
/// constant of its exponential decay in seconds.
struct Partial { var ratio, gain, decay: Double }

/// One strike: when it lands, its pitch and level, and how much faster its modes decay. `missed`
/// is struck damped, so the same bar stops sooner.
struct Strike { var pitch, gain, onset, damping: Double }

/// A set: the modes a strike excites, the mallet's contact, the room it is struck in, and the two
/// sounds made from it.
struct Material {
    var name: String
    var partials: [Partial]
    var touch, touchLow, touchHigh, touchDecay: Double
    /// The contact's rise, and the bar's: a real bar blooms a little after the mallet lands.
    var attack, bloom: Double
    /// How much of the short room to mix in (0 is dry), and how dark its tail is (a low-pass, Hz).
    var room, roomTone: Double
    var landed, missed: [Strike]
    var landedLength, missedLength: Double
    var landedPeak, missedPeak: Double
}

// The same pitches in every set, so a comparison hears the object and not the note. G4 is what
// macOS's own screenshot sound is tuned to; `missed` is a fifth below it, the direction Apple's
// own pairs move for the negative outcome.
let landedPitch = 392.00, missedPitch = 261.63 // G4, C4
let missedDamping = 1.5

let sets = [
    // The shipped Room (Sep 20): a tuned marimba bar, modes 1 : 4 : 10, a little air under it.
    // Kept as the reference the refinements below are heard against.
    Material(name: "room", partials: [
        Partial(ratio: 1.0, gain: 1.00, decay: 0.075),
        Partial(ratio: 4.0, gain: 0.11, decay: 0.045),
        Partial(ratio: 10.0, gain: 0.05, decay: 0.018),
    ], touch: 1.4, touchLow: 400, touchHigh: 3_000, touchDecay: 0.008, attack: 0.005, bloom: 0.005, room: 0.18, roomTone: 20_000,
       landed: [Strike(pitch: landedPitch, gain: 1, onset: 0, damping: 1)],
       missed: [Strike(pitch: missedPitch, gain: 1, onset: 0, damping: missedDamping)],
       landedLength: 0.700, missedLength: 0.500, landedPeak: -15, missedPeak: -18),
    // Room, quieter and softer: the mallet at less than half the level and darker, the bar
    // blooming over 12 ms behind it, the room's tail low-passed so it reads as air, not hiss.
    Material(name: "soft", partials: [
        Partial(ratio: 1.0, gain: 1.00, decay: 0.065),
        Partial(ratio: 4.0, gain: 0.10, decay: 0.040),
        Partial(ratio: 10.0, gain: 0.04, decay: 0.016),
    ], touch: 0.6, touchLow: 400, touchHigh: 1_800, touchDecay: 0.006, attack: 0.006, bloom: 0.012, room: 0.15, roomTone: 2_000,
       landed: [Strike(pitch: landedPitch, gain: 1, onset: 0, damping: 1)],
       missed: [Strike(pitch: missedPitch, gain: 1, onset: 0, damping: missedDamping)],
       landedLength: 0.560, missedLength: 0.420, landedPeak: -19, missedPeak: -22),
    // Soft with a longer bloom: the bar swells in over 28 ms under a faint contact, the way
    // macOS's own screenshot sound rises rather than strikes.
    Material(name: "bloom", partials: [
        Partial(ratio: 1.0, gain: 1.00, decay: 0.070),
        Partial(ratio: 4.0, gain: 0.09, decay: 0.045),
        Partial(ratio: 10.0, gain: 0.03, decay: 0.018),
    ], touch: 0.5, touchLow: 400, touchHigh: 1_600, touchDecay: 0.006, attack: 0.006, bloom: 0.028, room: 0.18, roomTone: 1_800,
       landed: [Strike(pitch: landedPitch, gain: 1, onset: 0, damping: 1)],
       missed: [Strike(pitch: missedPitch, gain: 1, onset: 0, damping: missedDamping)],
       landedLength: 0.600, missedLength: 0.440, landedPeak: -19, missedPeak: -22),
    // Soft, a fourth lower: D4, the root of the Shortcuts completion sound, with missed a fourth
    // below that at A3. Lower reads warmer; a lower bar also rings a little longer.
    Material(name: "deep", partials: [
        Partial(ratio: 1.0, gain: 1.00, decay: 0.080),
        Partial(ratio: 4.0, gain: 0.10, decay: 0.050),
        Partial(ratio: 10.0, gain: 0.04, decay: 0.020),
    ], touch: 0.6, touchLow: 300, touchHigh: 1_600, touchDecay: 0.006, attack: 0.006, bloom: 0.012, room: 0.15, roomTone: 2_000,
       landed: [Strike(pitch: 293.66, gain: 1, onset: 0, damping: 1)],
       missed: [Strike(pitch: 220.00, gain: 1, onset: 0, damping: missedDamping)],
       landedLength: 0.650, missedLength: 0.480, landedPeak: -19, missedPeak: -22),
]

let fadeOut = 0.080

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

/// One strike of `material`, added into `buffer` from its onset. Damping shortens every mode, so a
/// damped strike stops sooner instead of only sounding lower.
func play(_ strike: Strike, of material: Material, seed: UInt64, into buffer: inout [Double]) {
    let start = min(Int((strike.onset * rate).rounded()), buffer.count)
    var noise = SplitMix64(state: seed)
    var high = Biquad(cutoff: material.touchLow, lowPass: false)
    var low = Biquad(cutoff: material.touchHigh, lowPass: true)
    for i in start..<buffer.count {
        let t = Double(i - start) / rate
        var sample = 0.0
        for partial in material.partials {
            sample += partial.gain * exp(-t / (partial.decay / strike.damping)) * sin(2 * .pi * strike.pitch * partial.ratio * t)
        }
        let contact = material.touch * low.process(high.process(noise.next())) * exp(-t / material.touchDecay)
        let toneRise = t < material.bloom ? 0.5 - 0.5 * cos(.pi * t / material.bloom) : 1
        let contactRise = t < material.attack ? 0.5 - 0.5 * cos(.pi * t / material.attack) : 1
        buffer[i] += strike.gain * (toneRise * sample + contactRise * contact)
    }
}

/// A small room: early energy decaying over 45 ms, dense enough to read as air rather than echo,
/// and low-passed at `tone`, because a real room's tail is dark.
func room(_ signal: [Double], mix: Double, tone: Double) -> [Double] {
    guard mix > 0 else { return signal }
    let taps = Int(0.180 * rate)
    var impulse = [Double](repeating: 0, count: taps)
    var noise = SplitMix64(state: 0x5000_0007)
    let k = 1 - exp(-2 * Double.pi * tone / rate)
    var smoothed = 0.0
    for i in 0..<taps {
        let t = Double(i) / rate
        smoothed += (noise.next() - smoothed) * k
        impulse[i] = smoothed * exp(-t / 0.045) * (t < 0.004 ? t / 0.004 : 1)
    }
    let energy = impulse.reduce(0) { $0 + $1 * $1 }.squareRoot()
    for i in 0..<taps { impulse[i] /= energy }
    var wet = [Double](repeating: 0, count: signal.count)
    for (i, sample) in signal.enumerated() where sample != 0 {
        let last = min(taps, signal.count - i)
        for j in 0..<last { wet[i + j] += sample * impulse[j] }
    }
    return zip(signal, wet).map { $0 + mix * $1 }
}

func render(_ material: Material, landed: Bool) -> [Float] {
    let length = landed ? material.landedLength : material.missedLength
    var buffer = [Double](repeating: 0, count: Int((length * rate).rounded()))
    for (index, strike) in (landed ? material.landed : material.missed).enumerated() {
        play(strike, of: material, seed: UInt64(index + 1), into: &buffer)
    }
    buffer = room(buffer, mix: material.room, tone: material.roomTone)
    // The tail fades to exactly zero, so the file ends without a click.
    let fadeStart = buffer.count - Int((fadeOut * rate).rounded())
    for i in fadeStart..<buffer.count {
        buffer[i] *= 0.5 + 0.5 * cos(.pi * Double(i - fadeStart) / Double(buffer.count - 1 - fadeStart))
    }
    let peak = buffer.map(abs).max()!
    let target = pow(10, (landed ? material.landedPeak : material.missedPeak) / 20)
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

/// Duration, levels, where the energy sits, and how far the ring has fallen when the fade starts:
/// Apple's own confirmations are past -46 dB there, so the file ends by decay, not by the fade.
func report(_ name: String, _ samples: [Float]) {
    let peakLinear = Double(samples.map(abs).max()!)
    let peak = 20 * log10(peakLinear)
    let rms = 20 * log10((samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot())
    let band = bandShare(samples, low: 200, high: 4_000) * 100
    let window = Int(0.005 * rate)
    let fadeStart = max(0, samples.count - Int(fadeOut * rate) - window)
    let tailEnergy = (fadeStart..<(fadeStart + window)).reduce(0.0) { $0 + Double(samples[$1]) * Double(samples[$1]) } / Double(window)
    let tail = 20 * log10(tailEnergy.squareRoot() / peakLinear)
    print(String(format: "%-14@ %4.0f ms   peak %6.1f dBFS   rms %6.1f dBFS   200 Hz–4 kHz %5.1f %%   tail at fade %6.1f dB", name as NSString, Double(samples.count) / rate * 1000, peak, rms, band, tail))
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
