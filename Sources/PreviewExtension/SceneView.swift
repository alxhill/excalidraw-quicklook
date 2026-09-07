import AppKit

/// Draws the drawing as vectors at whatever zoom the enclosing scroll view is
/// at, so zooming in sharpens the strokes instead of magnifying pixels.
final class SceneView: NSView {
    private let scene: Scene
    private let background: CGColor

    /// Called with the click location in this view's coordinates.
    var onDoubleClick: ((CGPoint) -> Void)?

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

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else { return super.mouseDown(with: event) }
        onDoubleClick?(convert(event.locationInWindow, from: nil))
    }

    /// Trackpad pinch is handled by the scroll view; this adds the mouse and
    /// modifier-scroll equivalent.
    override func scrollWheel(with event: NSEvent) {
        let zooming = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option)
        guard zooming, let scrollView = enclosingScrollView else {
            return super.scrollWheel(with: event)
        }
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY * 0.01
            : event.scrollingDeltaY * 0.05
        guard delta != 0 else { return }
        let magnification = max(
            scrollView.minMagnification,
            min(scrollView.maxMagnification, scrollView.magnification * (1 + delta))
        )
        scrollView.setMagnification(magnification, centeredAt: convert(event.locationInWindow, from: nil))
    }
}

/// NSScrollView pins a document view smaller than the viewport to the top left;
/// this keeps it centred, which is what you want for a drawing zoomed to fit.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        if rect.width > documentView.frame.width {
            rect.origin.x = (documentView.frame.width - rect.width) / 2
        }
        if rect.height > documentView.frame.height {
            rect.origin.y = (documentView.frame.height - rect.height) / 2
        }
        return rect
    }
}
