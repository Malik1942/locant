import Accelerate
import Foundation
// Renders Locant's two interface sounds, `landed` and `missed` (specs/v0.8.1.md R60).
// A sound is one soft chord or note, voiced the way Apple voices a confirmation: a root with its
// fifth and octave sounding at once, rich harmonics that fall gently, two voices a few cents apart
// for warmth, a slow rise, a dark room. One gesture, never a melody, never a strike: every struck
// bar in earlier rounds read as sharp, because a strike begins with a contact. `missed` is the same
// voicing a fourth lower and damped, the same instrument saying no.
//
// Levels, lengths and what is above 4 kHz follow a measurement of macOS's own interface sounds
// (45 files, Sep 20 2026): confirmations last 420 to 755 ms and finish their own decay, peak
// between -21 and -7 dBFS, and hold essentially nothing above 4 kHz.
// Every number that shapes a set is below; change one, re-render, listen.
//
//   swiftc -O design/sound/render.swift -o design/sound/render
//   design/sound/render candidates <folder>   every set as WAV, for listening
//   design/sound/render ship <set>            one set as CAF into Locant/Feedback/Sounds (run from the repo root)

let rate = 48_000.0

/// How a voice is built: a harmonic series with amplitudes falling as 1/n^tilt, the upper
/// harmonics dying faster (decay / n^shine), two copies a few cents apart for warmth, and a small
/// downward glide at the onset, as a real string or tine has.
struct Timbre { var harmonics: Int; var tilt, shine, detuneCents, glideCents: Double }

/// One note of a chord: its pitch and level.
struct Note { var pitch, gain: Double }

/// A set: the timbre, its rise and decay, the room, and the two chords made from it. `missed` is
/// the same voicing a fourth lower, damped, so it reads as the same instrument saying no.
struct Material {
    var name: String
    var timbre: Timbre
    var attack, decay: Double
    /// How much room to mix in (0 is dry), how dark its tail is (a low-pass, Hz), how long it rings.
    var room, roomTone, roomDecay: Double
    var landed, missed: [Note]
    var missedDamping: Double
    var landedLength, missedLength: Double
    var landedPeak, missedPeak: Double
}

// One root for every set, so a comparison hears the instrument and not the key: D4, the root of
// the Shortcuts completion sound, voiced 1 : 5 : 8 as Apple voices a confirmation. `missed` is the
// same voicing a fourth lower, on A3.
let root = 293.66, lowerRoot = 220.00
func chord(_ base: Double, fifth: Double, octave: Double) -> [Note] {
    [Note(pitch: base, gain: 1), Note(pitch: base * 1.5, gain: fifth), Note(pitch: base * 2, gain: octave)]
}

let sets = [
    // A warm chord, the way the startup chime and the Shortcuts completion are voiced: six
    // harmonics falling gently, chorused two and a half cents, rising over 30 ms into a dark room.
    Material(name: "chord", timbre: Timbre(harmonics: 6, tilt: 1.6, shine: 0.7, detuneCents: 2.5, glideCents: 6),
             attack: 0.030, decay: 0.080, room: 0.20, roomTone: 1_600, roomDecay: 0.070,
             landed: chord(root, fifth: 0.55, octave: 0.35), missed: chord(lowerRoot, fifth: 0.55, octave: 0.35), missedDamping: 1.5,
             landedLength: 0.700, missedLength: 0.500, landedPeak: -19, missedPeak: -22),
    // The same chord as a pad: fewer, rounder harmonics, a wider chorus, a 60 ms swell and more
    // room. The softest edge of the three; nothing in it arrives suddenly.
    Material(name: "pad", timbre: Timbre(harmonics: 4, tilt: 2.0, shine: 0.5, detuneCents: 4, glideCents: 0),
             attack: 0.060, decay: 0.075, room: 0.28, roomTone: 1_400, roomDecay: 0.090,
             landed: chord(root, fifth: 0.6, octave: 0.4), missed: chord(lowerRoot, fifth: 0.6, octave: 0.4), missedDamping: 1.5,
             landedLength: 0.700, missedLength: 0.560, landedPeak: -19, missedPeak: -22),
    // A single plucked note, a thumb piano: eight harmonics with the upper ones gone in a moment,
    // a small glide as the tine settles, a quick but soft rise. One note, the octave carried by the
    // timbre rather than a second voice.
    Material(name: "pluck", timbre: Timbre(harmonics: 8, tilt: 1.2, shine: 1.2, detuneCents: 1.5, glideCents: 10),
             attack: 0.008, decay: 0.085, room: 0.15, roomTone: 1_600, roomDecay: 0.060,
             landed: [Note(pitch: root, gain: 1)], missed: [Note(pitch: lowerRoot, gain: 1)], missedDamping: 1.5,
             landedLength: 0.650, missedLength: 0.470, landedPeak: -19, missedPeak: -22),
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

/// One note of `material`, added into `buffer`: two voices a few cents apart, each a harmonic
/// series whose upper harmonics die faster, under a raised-cosine rise. `damping` shortens every
/// harmonic, so a damped chord stops sooner instead of only sounding lower.
func play(_ note: Note, of material: Material, damping: Double, into buffer: inout [Double]) {
    let timbre = material.timbre
    let detune = pow(2, timbre.detuneCents / 1200)
    for voice in [1 / detune, detune] {
        for n in 1...timbre.harmonics {
            let amplitude = note.gain / pow(Double(n), timbre.tilt) / 2
            let decay = material.decay / pow(Double(n), timbre.shine) / damping
            var phase = 0.0
            for i in 0..<buffer.count {
                let t = Double(i) / rate
                // The glide: a few cents high at the onset, settling over 30 ms.
                let glide = pow(2, timbre.glideCents * exp(-t / 0.030) / 1200)
                phase += 2 * .pi * note.pitch * Double(n) * voice * glide / rate
                let rise = t < material.attack ? 0.5 - 0.5 * cos(.pi * t / material.attack) : 1
                buffer[i] += amplitude * exp(-t / decay) * rise * sin(phase)
            }
        }
    }
}

/// A small room: dense early energy decaying over `decay`, low-passed at `tone`, because a real
/// room's tail is dark.
func room(_ signal: [Double], mix: Double, tone: Double, decay: Double) -> [Double] {
    guard mix > 0 else { return signal }
    let taps = Int(decay * 4 * rate)
    var impulse = [Double](repeating: 0, count: taps)
    var noise = SplitMix64(state: 0x5000_0007)
    let k = 1 - exp(-2 * Double.pi * tone / rate)
    var smoothed = 0.0
    for i in 0..<taps {
        let t = Double(i) / rate
        smoothed += (noise.next() - smoothed) * k
        impulse[i] = smoothed * exp(-t / decay) * (t < 0.004 ? t / 0.004 : 1)
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
    for note in landed ? material.landed : material.missed {
        play(note, of: material, damping: landed ? 1 : material.missedDamping, into: &buffer)
    }
    buffer = room(buffer, mix: material.room, tone: material.roomTone, decay: material.roomDecay)
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
