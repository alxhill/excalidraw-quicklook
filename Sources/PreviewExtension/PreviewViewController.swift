import AppKit
import Quartz

/// The spacebar preview: a scrollable, zoomable canvas.
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let canvas = SceneCanvas()

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
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 700))

        canvas.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(canvas)
        container.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
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
            canvas.show(scene)

            // Opens the panel at the drawing's shape, capped so a wall-sized
            // canvas does not ask for a wall-sized window.
            let contentSize = canvas.contentSize
            let cap: CGFloat = 1600
            let shrink = min(1, min(cap / contentSize.width, cap / contentSize.height))
            preferredContentSize = CGSize(
                width: contentSize.width * shrink, height: contentSize.height * shrink
            )
            handler(nil)
        } catch {
            canvas.isHidden = true
            messageLabel.isHidden = false
            messageLabel.stringValue = error.localizedDescription
            handler(nil)
        }
    }
}
