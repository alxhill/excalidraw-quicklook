import AppKit

/// A drawing on a scrollable, zoomable canvas. Shared by the QuickLook preview
/// and the viewer app so both pan and zoom the same way.
final class SceneCanvas: NSView {
    private let scrollView = CanvasScrollView()
    private var needsFit = false
    private var viewportSize: CGSize = .zero

    /// The drawing's natural size in points, once one is loaded.
    private(set) var contentSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = CanvasClipView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.borderType = .noBorder
        scrollView.onDoubleClick = { [weak self] point in self?.toggleZoom(at: point) }
        scrollView.allowsMagnification = true
        scrollView.maxMagnification = 12
        scrollView.minMagnification = 0.02

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    var hasScene: Bool { scrollView.documentView != nil }

    func show(_ scene: Scene, padding: CGFloat = 16) {
        contentSize = SceneRenderer.contentSize(of: scene, padding: padding)

        scrollView.documentView = SceneView(scene: scene, size: contentSize)
        scrollView.backgroundColor =
            NSColor(cgColor: Colors.parse(scene.backgroundColor) ?? CGColor(gray: 1, alpha: 1))
            ?? .textBackgroundColor

        needsFit = true
        needsLayout = true
    }

    func clear() {
        scrollView.documentView = nil
        contentSize = .zero
        needsFit = false
    }

    override func layout() {
        super.layout()
        let previousViewport = viewportSize
        viewportSize = scrollView.contentView.frame.size
        guard hasScene, viewportSize.width > 1, viewportSize.height > 1 else { return }

        if needsFit {
            needsFit = false
            let fitted = fitMagnification()
            // Small drawings scale up a little rather than sitting tiny in the
            // middle of the window, but never past 3:1.
            scrollView.magnification = min(fitted, 3)
            scrollView.minMagnification = min(fitted, 1) / 4
            centre()
        } else if previousViewport != viewportSize, previousViewport != .zero {
            // The clip view keeps its origin corner fixed on resize; keep what
            // was in the middle of the window in the middle instead.
            let scale = magnification
            var origin = scrollView.contentView.bounds.origin
            origin.x += (previousViewport.width - viewportSize.width) / (2 * scale)
            origin.y += (previousViewport.height - viewportSize.height) / (2 * scale)
            scrollView.scroll(toOrigin: origin)
        }
    }

    // MARK: - Zoom

    var magnification: CGFloat { scrollView.magnification }

    func zoomToFit() {
        setMagnification(min(fitMagnification(), 3))
        centre()
    }
    func zoomToActualSize() { setMagnification(1) }
    func zoomIn() { setMagnification(magnification * 1.25) }
    func zoomOut() { setMagnification(magnification / 1.25) }

    /// Zoom about the middle of what is on screen, so the thing being looked
    /// at stays put.
    private func setMagnification(_ value: CGFloat) {
        let centre = CGPoint(x: scrollView.contentView.bounds.midX, y: scrollView.contentView.bounds.midY)
        scrollView.setMagnification(clamp(value), centeredAt: centre)
    }

    /// Puts the middle of the drawing in the middle of the viewport.
    private func centre() {
        guard let document = scrollView.documentView else { return }
        let visible = scrollView.contentView.bounds
        scrollView.scroll(toOrigin:
            CGPoint(x: document.frame.midX - visible.width / 2, y: document.frame.midY - visible.height / 2))
    }

    private func clamp(_ magnification: CGFloat) -> CGFloat {
        max(scrollView.minMagnification, min(scrollView.maxMagnification, magnification))
    }

    /// The magnification at which the whole drawing is visible.
    private func fitMagnification() -> CGFloat {
        guard let document = scrollView.documentView,
              document.bounds.width > 0, document.bounds.height > 0 else { return 1 }
        let visible = scrollView.bounds.size
        guard visible.width > 0, visible.height > 0 else { return 1 }
        return min(visible.width / document.bounds.width, visible.height / document.bounds.height)
    }

    private func toggleZoom(at point: CGPoint) {
        guard let document = scrollView.documentView else { return }
        let fitted = min(fitMagnification(), 3)
        let isFitted = abs(magnification - fitted) < 0.01
        let target = clamp(isFitted ? max(1, fitted * 2) : fitted)

        // Zooming in keeps the clicked point still. Zooming back out should
        // end with the drawing centred, so pick the anchor that makes the
        // zoom land there: a point p stays fixed on screen, so the viewport
        // centre v moves to p - (p - v) * (current / target).
        var anchor = point
        if isFitted == false {
            let visible = scrollView.contentView.bounds
            let v = CGPoint(x: visible.midX, y: visible.midY)
            let c = CGPoint(x: document.frame.midX, y: document.frame.midY)
            let k = magnification / target
            guard abs(1 - k) > 0.001 else { return centre() }
            anchor = CGPoint(x: (c.x - v.x * k) / (1 - k), y: (c.y - v.y * k) / (1 - k))
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            scrollView.animator().setMagnification(target, centeredAt: anchor)
        }, completionHandler: { [weak self] in
            if !isFitted { self?.centre() }
        })
    }
}
