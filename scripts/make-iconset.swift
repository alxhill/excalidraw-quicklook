// Wraps the rendered icon drawing in the rounded card macOS expects and writes
// an .iconset for iconutil. Run by the Makefile:
//
//     swift scripts/make-iconset.swift sketch.png out.iconset
//
// The geometry is Apple's: on a 1024pt canvas the artwork occupies the middle
// 824pt with an 185.4pt corner radius, which is what makes an icon sit at the
// same size as every other icon in the Dock.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-iconset: \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else { fail("usage: make-iconset <sketch.png> <out.iconset>") }
let sketchURL = URL(fileURLWithPath: arguments[0])
let outputDirectory = URL(fileURLWithPath: arguments[1])

guard let source = CGImageSourceCreateWithURL(sketchURL as CFURL, nil),
      let sketch = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("cannot read \(sketchURL.path)")
}

let card = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let edge = CGColor(srgbRed: 0.87, green: 0.87, blue: 0.88, alpha: 1)

func render(side: CGFloat) -> CGImage? {
    let pixels = Int(side)
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let margin = side * 100 / 1024
    let radius = side * 185.4 / 1024
    let bounds = CGRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2)
    let shape = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.setFillColor(card)
    ctx.addPath(shape)
    ctx.fillPath()

    // The sketch carries the same white background, so letterboxing it inside
    // the card leaves no seam — and fitting rather than filling keeps the
    // hand-drawn strokes away from the rounded edge.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.interpolationQuality = .high
    let scale = min(bounds.width / CGFloat(sketch.width), bounds.height / CGFloat(sketch.height))
    let size = CGSize(width: CGFloat(sketch.width) * scale, height: CGFloat(sketch.height) * scale)
    ctx.draw(sketch, in: CGRect(
        x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
        width: size.width, height: size.height
    ))
    ctx.restoreGState()

    // A hairline keeps the white card off a white background.
    ctx.setStrokeColor(edge)
    ctx.setLineWidth(max(1, side / 512))
    ctx.addPath(shape)
    ctx.strokePath()

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fail("cannot write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("failed to encode \(url.path)") }
}

try? FileManager.default.removeItem(at: outputDirectory)
do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
} catch { fail(error.localizedDescription) }

// The set iconutil expects: every size at 1x and 2x.
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let side = points * scale
        guard let image = render(side: CGFloat(side)) else { fail("cannot render \(side)px") }
        let suffix = scale == 2 ? "@2x" : ""
        write(image, to: outputDirectory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}

print("\(outputDirectory.lastPathComponent) — 10 images")
