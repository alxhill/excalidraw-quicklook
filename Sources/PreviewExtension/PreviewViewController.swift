import AppKit
import Quartz

/// The spacebar preview. Renders once at a generous size and lets the image
/// view scale it to whatever the QuickLook panel ends up being.
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let imageView: NSImageView = {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let messageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    override func loadView() {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        container.addSubview(imageView)
        container.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
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
            let scale = view.window?.backingScaleFactor ?? 2
            guard let image = SceneRenderer.render(
                scene,
                options: RenderOptions(
                    maximumSize: CGSize(width: 1800, height: 1400),
                    scale: scale,
                    padding: 16
                )
            ) else { throw SceneParseError.empty }

            let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            imageView.image = NSImage(cgImage: image, size: size)
            view.layer?.backgroundColor = NSColor.white.cgColor
            preferredContentSize = size
            handler(nil)
        } catch {
            imageView.isHidden = true
            messageLabel.isHidden = false
            messageLabel.stringValue = error.localizedDescription
            handler(nil)
        }
    }
}
