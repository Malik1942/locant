#!/usr/bin/env swift
// Blurs the text in a @2x screenshot so a real-screen fixture can be public, then reads it back and
// lists any text still legible (specs/capture-shapes.md, section 3). Two Vision requests find the text,
// the rectangle detector and the recognizer (which also finds Chinese and whole lines); the pass repeats
// until a read finds none. Neither sees text cut off by the capture's edge, so keep-top-px crops it away.
// Usage: swift scripts/blur-fixture-text.swift <in.png> <out.png> [keep-top-px]
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
guard args.count == 3 || args.count == 4 else { print("usage: blur-fixture-text <in.png> <out.png> [keep-top-px]"); exit(2) }
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
guard let rep = NSBitmapImageRep(data: try Data(contentsOf: input)), let image = rep.cgImage else {
    print("cannot read \(input.path)"); exit(1)
}
let width = image.width, height = image.height
let keep = args.count == 4 ? Int(args[3]) ?? 0 : height // rows kept from the top
guard keep > 0, keep <= height else { print("keep-top-px must be 1...\(height)"); exit(2) }
let original = CIImage(cgImage: image)
let context = CIContext()
let languages = ["en-US", "zh-Hans"]

func textBoxes(in cg: CGImage) throws -> [CGRect] {
    let detect = VNDetectTextRectanglesRequest()
    let read = VNRecognizeTextRequest()
    read.recognitionLevel = .accurate
    read.recognitionLanguages = languages
    read.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: cg).perform([detect, read])
    // Vision's boxes are normalized with the origin at the bottom left, as Core Image's are.
    return (detect.results ?? []).map { VNImageRectForNormalizedRect($0.boundingBox, width, height) }
        + (read.results ?? []).map { VNImageRectForNormalizedRect($0.boundingBox, width, height) }
}

var result = original
var current = image
var blurred = 0
for _ in 1...4 {
    let boxes = try textBoxes(in: current)
    if boxes.isEmpty { break }
    for found in boxes {
        // A bigger line gets a bigger blur: large type survives a small one.
        let sigma = max(8, Double(found.height) * 0.4)
        let box = found.insetBy(dx: -6, dy: -6).integral
        result = original.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: box).composited(over: result)
    }
    blurred += boxes.count
    guard let next = context.createCGImage(result, from: original.extent) else { print("cannot render"); exit(1) }
    current = next
}
guard let kept = current.cropping(to: CGRect(x: 0, y: 0, width: width, height: keep)) else { print("cannot crop"); exit(1) }
let out = NSBitmapImageRep(cgImage: kept)
out.size = NSSize(width: CGFloat(width) / 2, height: CGFloat(keep) / 2) // @2x, as the capture was
guard let png = out.representation(using: .png, properties: [:]) else { print("cannot encode"); exit(1) }
try png.write(to: output)
let read = VNRecognizeTextRequest()
read.recognitionLevel = .accurate
read.recognitionLanguages = languages
try VNImageRequestHandler(cgImage: kept).perform([read])
let legible = (read.results ?? []).compactMap { $0.topCandidates(1).first?.string }
print("\(output.lastPathComponent): blurred \(blurred) text boxes; still legible: \(legible.isEmpty ? "none" : legible.joined(separator: " | "))")
