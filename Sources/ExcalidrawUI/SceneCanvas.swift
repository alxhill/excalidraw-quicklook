import AppKit

/// A drawing on a scrollable, zoomable canvas. Shared by the QuickLook preview
/// and the viewer app so both pan and zoom the same way.
final class SceneCanvas: NSView {
    private let scrollView = NSScrollView()
    private var needsFit = false

    /// The drawing's natural size in points, once one is loaded.
    private(set) var contentSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
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

        let sceneView = SceneView(scene: scene, size: contentSize)
        sceneView.onDoubleClick = { [weak self] point in self?.toggleZoom(at: point) }
        scrollView.documentView = sceneView
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
        guard needsFit, hasScene, scrollView.bounds.width > 1 else { return }
        needsFit = false
        let fitted = fitMagnification()
        // Small drawings scale up a little rather than sitting tiny in the
        // middle of the window, but never past 3:1.
        scrollView.magnification = min(fitted, 3)
        scrollView.minMagnification = min(fitted, 1) / 4
    }

    // MARK: - Zoom

    var magnification: CGFloat { scrollView.magnification }

    func zoomToFit() { setMagnification(min(fitMagnification(), 3)) }
    func zoomToActualSize() { setMagnification(1) }
    func zoomIn() { setMagnification(magnification * 1.25) }
    func zoomOut() { setMagnification(magnification / 1.25) }

    /// Zoom about the middle of what is on screen, so the thing being looked
    /// at stays put.
    private func setMagnification(_ value: CGFloat) {
        let centre = CGPoint(x: scrollView.contentView.bounds.midX, y: scrollView.contentView.bounds.midY)
        scrollView.setMagnification(clamp(value), centeredAt: centre)
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
        let fitted = min(fitMagnification(), 3)
        let isFitted = abs(magnification - fitted) < 0.01
        let target = isFitted ? max(1, fitted * 2) : fitted
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            scrollView.animator().setMagnification(clamp(target), centeredAt: point)
        }
    }
}
