import AppKit
import CoreGraphics
import Foundation
import QuickLookThumbnailing

/// Finder icons. Fills the requested box as far as the drawing's aspect ratio
/// allows, so a wide diagram stays wide instead of being letterboxed.
@objc(ThumbnailProvider)
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        Fonts.registerBundledFonts(in: Bundle.main.resourceURL?.appendingPathComponent("Fonts"))

        do {
            let scene = try SceneParser.parse(data: try Data(contentsOf: request.fileURL))
            guard let image = SceneRenderer.render(
                scene,
                options: RenderOptions(
                    maximumSize: request.maximumSize,
                    scale: request.scale,
                    padding: 4,
                    maximumZoom: 1
                )
            ) else { throw SceneParseError.empty }

            let size = CGSize(
                width: CGFloat(image.width) / request.scale,
                height: CGFloat(image.height) / request.scale
            )
            // Drawn through AppKit rather than the CGContext block: that
            // block's context is sized in pixels while contextSize is in
            // points, so at scale 2 a CoreGraphics rect lands in one corner.
            handler(QLThumbnailReply(contextSize: size, currentContextDrawing: {
                NSImage(cgImage: image, size: size)
                    .draw(in: NSRect(origin: .zero, size: size))
                return true
            }), nil)
        } catch {
            handler(nil, error)
        }
    }
}
