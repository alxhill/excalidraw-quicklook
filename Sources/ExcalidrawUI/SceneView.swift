import AppKit

/// Draws the drawing as vectors at whatever zoom the enclosing scroll view is
/// at, so zooming in sharpens the strokes instead of magnifying pixels.
final class SceneView: NSView {
    private let scene: Scene
    private let background: CGColor

    init(scene: Scene, size: CGSize) {
        self.scene = scene
        self.background =
            Colors.parse(scene.backgroundColor) ?? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        super.init(frame: CGRect(origin: .zero, size: size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }

    override var isOpaque: Bool { true }

    private var boundsObserver: NSObjectProtocol?

    // QuickLook hosts an extension's views layer-backed, and a layer-backed
    // document view is rasterised at the window's scale and then magnified —
    // which would blur the drawing on zoom even though it is drawn as vectors.
    // Raising contentsScale with the magnification makes it re-render sharp.
    // Capped at 2x the window scale: the backing store grows with the square
    // of this, and past that the raster is already finer than the display.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard boundsObserver == nil, let clipView = enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main
        ) { [weak self] _ in
            self?.matchContentsScaleToMagnification()
        }
        matchContentsScaleToMagnification()
    }

    private func matchContentsScaleToMagnification() {
        guard let layer else { return }
        let windowScale = window?.backingScaleFactor ?? 2
        let magnification = enclosingScrollView?.magnification ?? 1
        let wanted = min(windowScale * max(magnification, 1), windowScale * 2)
        guard abs(layer.contentsScale - wanted) > 0.01 else { return }
        layer.contentsScale = wanted
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(background)
        ctx.fill(dirtyRect)
        // The view is sized to the drawing's natural size, so this fits at 1:1
        // and the scroll view's magnification supplies the zoom.
        SceneRenderer.draw(scene, in: ctx, fitting: bounds, padding: 0)
    }
}

/// Lets the drawing be panned anywhere, like Excalidraw's own canvas, instead
/// of pinning a document smaller than the viewport in place. A sliver of the
/// drawing always stays on screen so it cannot be lost off the edge.
final class CanvasClipView: NSClipView {
    /// How much of the drawing must remain visible, in screen points.
    var keepVisible: CGFloat = 48

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        guard let documentView, proposedBounds.width > 0, proposedBounds.height > 0 else {
            return super.constrainBoundsRect(proposedBounds)
        }
        let doc = documentView.frame
        // Bounds are in document units, the frame in screen points; the ratio
        // is the scroll view's magnification.
        let inset = keepVisible / (frame.width / proposedBounds.width)
        var rect = proposedBounds
        rect.origin.x = min(max(rect.origin.x, doc.minX + inset - rect.width), doc.maxX - inset)
        rect.origin.y = min(max(rect.origin.y, doc.minY + inset - rect.height), doc.maxY - inset)
        return rect
    }
}
