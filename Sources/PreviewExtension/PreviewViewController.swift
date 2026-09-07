import AppKit
import Quartz

/// The spacebar preview: a scrollable, zoomable canvas.
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let scrollView = NSScrollView()

    private let messageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private var zoomedToFit = false
    private var fittedMagnification: CGFloat = 1

    override func loadView() {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 700))

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.allowsMagnification = true
        scrollView.maxMagnification = 12
        scrollView.minMagnification = 0.02

        container.addSubview(scrollView)
        container.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            messageLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            messageLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor, constant: 16
            ),
        ])
        view = container
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        Fonts.registerBundledFonts(in: Bundle.main.resourceURL?.appendingPathComponent("Fonts"))

        do {
            let scene = try SceneParser.parse(data: try Data(contentsOf: url))
            let contentSize = SceneRenderer.contentSize(of: scene, padding: 16)

            let sceneView = SceneView(scene: scene, size: contentSize)
            sceneView.onDoubleClick = { [weak self] point in
                self?.toggleZoom(at: point)
            }
            scrollView.documentView = sceneView
            scrollView.backgroundColor =
                NSColor(cgColor: Colors.parse(scene.backgroundColor) ?? CGColor(gray: 1, alpha: 1))
                ?? .textBackgroundColor

            // Opens the panel at the drawing's shape, capped so a wall-sized
            // canvas does not ask for a wall-sized window.
            let cap: CGFloat = 1600
            let shrink = min(1, min(cap / contentSize.width, cap / contentSize.height))
            preferredContentSize = CGSize(
                width: contentSize.width * shrink, height: contentSize.height * shrink
            )
            zoomedToFit = false
            handler(nil)
        } catch {
            scrollView.isHidden = true
            messageLabel.isHidden = false
            messageLabel.stringValue = error.localizedDescription
            handler(nil)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !zoomedToFit, scrollView.documentView != nil, scrollView.bounds.width > 1 else { return }
        zoomedToFit = true
        fittedMagnification = fitMagnification()
        // Small drawings scale up a little rather than sitting tiny in the
        // middle of the panel, but never past 3:1.
        scrollView.magnification = min(fittedMagnification, 3)
        scrollView.minMagnification = min(fittedMagnification, 1) / 4
    }

    private func fitMagnification() -> CGFloat {
        guard let document = scrollView.documentView,
              document.bounds.width > 0, document.bounds.height > 0 else { return 1 }
        let visible = scrollView.bounds.size
        guard visible.width > 0, visible.height > 0 else { return 1 }
        return min(visible.width / document.bounds.width, visible.height / document.bounds.height)
    }

    private func toggleZoom(at point: CGPoint) {
        let fitted = min(fitMagnification(), 3)
        let isFitted = abs(scrollView.magnification - fitted) < 0.01
        let target = isFitted ? max(1, fitted * 2) : fitted
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            scrollView.animator().setMagnification(target, centeredAt: point)
        }
    }
}
