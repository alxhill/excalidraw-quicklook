import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Development harness: renders a drawing to PNG without going through Finder,
// which is the only sane way to iterate on the renderer.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("excalidraw-render: \(message)\n".utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var size: CGFloat = 1400
var scale: CGFloat = 2
var positional: [String] = []

var index = 0
while index < arguments.count {
    switch arguments[index] {
    case "--size":
        index += 1
        size = CGFloat(Double(arguments[index]) ?? 1400)
    case "--scale":
        index += 1
        scale = CGFloat(Double(arguments[index]) ?? 2)
    case "-h", "--help":
        print("usage: excalidraw-render <input.excalidraw> <output.png> [--size N] [--scale N]")
        exit(0)
    default:
        positional.append(arguments[index])
    }
    index += 1
}

guard positional.count == 2 else {
    fail("usage: excalidraw-render <input.excalidraw> <output.png> [--size N] [--scale N]")
}

let input = URL(fileURLWithPath: positional[0])
let output = URL(fileURLWithPath: positional[1])

Fonts.registerBundledFonts(
    in: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/Fonts")
)

do {
    let scene = try SceneParser.parse(data: try Data(contentsOf: input))
    guard let image = SceneRenderer.render(
        scene,
        options: RenderOptions(maximumSize: CGSize(width: size, height: size), scale: scale)
    ) else { fail("nothing to render") }

    guard let destination = CGImageDestinationCreateWithURL(
        output as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fail("cannot write \(output.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("failed to encode PNG") }

    print("\(output.path) \(image.width)x\(image.height) — \(scene.elements.count) elements")
} catch {
    fail(error.localizedDescription)
}
