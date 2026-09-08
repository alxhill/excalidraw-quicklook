import AppKit

/// One window showing one drawing. Read-only on purpose: it parses the file,
/// draws it, and otherwise exists to hand the file to an editor.
final class ViewerWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    private let canvas = SceneCanvas()
    private let container = DropView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let emptyState = NSStackView()
    private var noticeTimer: Timer?
    private var hasSizedToDrawing = false

    private(set) var fileURL: URL?
    private var scene: Scene?

    /// Set by the app delegate: window bookkeeping and files dropped here.
    var onClose: ((ViewerWindow) -> Void)?
    var onOpenFiles: (([URL]) -> Void)?

    init() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Excalidraw QuickLook"
        window.tabbingMode = .disallowed
        super.init(window: window)

        window.delegate = self
        window.contentView = buildContentView()
        window.toolbar = buildToolbar()
        window.toolbarStyle = .unified
        showEmptyState(title: "Excalidraw QuickLook", welcomeText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Views

    private func buildContentView() -> NSView {
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.isHidden = true

        emptyState.orientation = .vertical
        emptyState.alignment = .centerX
        emptyState.spacing = 16
        emptyState.translatesAutoresizingMaskIntoConstraints = false

        let statusBar = NSView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(separator)
        statusBar.addSubview(statusLabel)

        container.onDrop = { [weak self] urls in self?.onOpenFiles?(urls) }
        container.addSubview(canvas)
        container.addSubview(emptyState)
        container.addSubview(statusBar)

        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            emptyState.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            emptyState.widthAnchor.constraint(lessThanOrEqualToConstant: 460),

            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),

            separator.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: statusBar.topAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
        ])
        return container
    }

    private var welcomeText: String {
        """
        Open an .excalidraw file to look at it, or drop one here.

        Finder previews and icons come from the two extensions inside this app, \
        which stop working if you move or delete it.
        """
    }

    private func showEmptyState(title heading: String, _ message: String) {
        emptyState.subviews.forEach { $0.removeFromSuperview() }

        let title = NSTextField(labelWithString: heading)
        title.font = .systemFont(ofSize: 20, weight: .medium)

        let body = NSTextField(wrappingLabelWithString: message)
        body.alignment = .center
        body.textColor = .secondaryLabelColor
        body.font = .systemFont(ofSize: 13)

        // Targetless, like the menu items: the app delegate answers this.
        let button = NSButton(
            title: "Open Drawing…", target: nil, action: #selector(AppDelegate.openDocument(_:))
        )
        button.bezelStyle = .rounded

        emptyState.addView(title, in: .center)
        emptyState.addView(body, in: .center)
        emptyState.addView(button, in: .center)
        emptyState.isHidden = false
        canvas.isHidden = true
    }

    // MARK: - Loading

    func open(_ url: URL) {
        fileURL = url
        window?.title = url.lastPathComponent
        window?.representedURL = url
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        reload(self)
    }

    @objc func reload(_ sender: Any?) {
        guard let fileURL else { return }
        do {
            let scene = try SceneParser.parse(data: try Data(contentsOf: fileURL))
            self.scene = scene
            canvas.show(scene)
            canvas.isHidden = false
            emptyState.isHidden = true
            sizeToDrawing()
            setStatus(describe(scene))
        } catch {
            scene = nil
            canvas.clear()
            showEmptyState(title: fileURL.lastPathComponent, error.localizedDescription)
            setStatus(abbreviated(fileURL))
        }
        window?.toolbar?.validateVisibleItems()
    }

    /// A fresh window takes the drawing's shape, within reason. Once the person
    /// has resized it, their size wins.
    private func sizeToDrawing() {
        guard !hasSizedToDrawing, let window, let screen = window.screen ?? NSScreen.main else { return }
        hasSizedToDrawing = true

        let room = screen.visibleFrame.size
        let drawing = canvas.contentSize
        let shrink = min(1, min(room.width * 0.8 / drawing.width, room.height * 0.85 / drawing.height))
        let wanted = CGSize(
            width: max(560, drawing.width * shrink),
            height: max(420, drawing.height * shrink)
        )
        window.setContentSize(wanted)
        window.center()
    }

    private func describe(_ scene: Scene) -> String {
        let count = scene.elements.count
        let elements = count == 1 ? "1 element" : "\(count) elements"
        guard let fileURL else { return elements }
        return "\(elements) · \(abbreviated(fileURL))"
    }

    private func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Status line

    private func setStatus(_ text: String) {
        noticeTimer?.invalidate()
        noticeTimer = nil
        statusLabel.stringValue = text
        statusLabel.textColor = .secondaryLabelColor
    }

    /// Says something for a few seconds, then goes back to describing the file.
    private func notice(_ text: String) {
        noticeTimer?.invalidate()
        statusLabel.stringValue = text
        statusLabel.textColor = .labelColor
        noticeTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            guard let self else { return }
            setStatus(scene.map(describe) ?? fileURL.map(abbreviated) ?? "")
        }
    }

    // MARK: - Actions

    @objc func openInExcalidraw(_ sender: Any?) {
        guard let fileURL else { return }
        switch OpenIn.excalidraw(fileURL) {
        case .app, .website:
            break
        case .websiteWithoutDrawing:
            notice("excalidraw.com opened — drop \(fileURL.lastPathComponent) onto the canvas to load it.")
        }
    }

    @objc func openInEditor(_ sender: Any?) {
        guard let fileURL, let editor = OpenIn.editor else { return }
        OpenIn.open(fileURL, with: editor)
    }

    @objc func revealInFinder(_ sender: Any?) {
        guard let fileURL else { return }
        OpenIn.reveal(fileURL)
    }

    @objc func copy(_ sender: Any?) {
        guard let scene, let image = SceneRenderer.render(
            scene, options: RenderOptions(maximumSize: CGSize(width: 4000, height: 4000), maximumZoom: 1)
        ) else { return }

        let representation = NSBitmapImageRep(cgImage: image)
        guard let png = representation.representation(using: .png, properties: [:]) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = representation.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        notice("Copied the drawing as a PNG image.")
    }

    @objc func copyFilePath(_ sender: Any?) {
        guard let fileURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fileURL.path, forType: .string)
        notice("Copied \(abbreviated(fileURL)).")
    }

    @objc func zoomToFit(_ sender: Any?) { canvas.zoomToFit() }
    @objc func zoomToActualSize(_ sender: Any?) { canvas.zoomToActualSize() }
    @objc func zoomInCanvas(_ sender: Any?) { canvas.zoomIn() }
    @objc func zoomOutCanvas(_ sender: Any?) { canvas.zoomOut() }

    // MARK: - Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { isAvailable(menuItem.action) }

    @objc func validateToolbarItem(_ item: NSToolbarItem) -> Bool { isAvailable(item.action) }

    private func isAvailable(_ action: Selector?) -> Bool {
        switch action {
        case #selector(openInEditor(_:)):
            return fileURL != nil && OpenIn.editor != nil
        case #selector(openInExcalidraw(_:)), #selector(revealInFinder(_:)),
             #selector(copyFilePath(_:)), #selector(reload(_:)):
            return fileURL != nil
        case #selector(copy(_:)), #selector(zoomToFit(_:)), #selector(zoomToActualSize(_:)),
             #selector(zoomInCanvas(_:)), #selector(zoomOutCanvas(_:)):
            return scene != nil
        default:
            return true
        }
    }

    // MARK: - Toolbar

    private enum Item {
        static let fit = NSToolbarItem.Identifier("fit")
        static let zoomOut = NSToolbarItem.Identifier("zoomOut")
        static let zoomIn = NSToolbarItem.Identifier("zoomIn")
        static let excalidraw = NSToolbarItem.Identifier("excalidraw")
        static let editor = NSToolbarItem.Identifier("editor")
        static let finder = NSToolbarItem.Identifier("finder")
    }

    private func buildToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "ViewerToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Item.fit, Item.zoomOut, Item.zoomIn,
            .flexibleSpace,
            Item.excalidraw, Item.editor, Item.finder,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Item.fit:
            return item(
                identifier, "Fit", "arrow.up.left.and.down.right.magnifyingglass",
                #selector(zoomToFit(_:))
            )
        case Item.zoomOut:
            return item(identifier, "Zoom Out", "minus.magnifyingglass", #selector(zoomOutCanvas(_:)))
        case Item.zoomIn:
            return item(identifier, "Zoom In", "plus.magnifyingglass", #selector(zoomInCanvas(_:)))
        case Item.excalidraw:
            let label = OpenIn.excalidrawApp.map(OpenIn.name(of:)) ?? "excalidraw.com"
            return item(identifier, label, "square.and.pencil", #selector(openInExcalidraw(_:)))
        case Item.editor:
            let label = OpenIn.editor.map(OpenIn.name(of:)) ?? "VS Code"
            return item(
                identifier, label, "chevron.left.forwardslash.chevron.right", #selector(openInEditor(_:))
            )
        case Item.finder:
            return item(identifier, "Reveal", "folder", #selector(revealInFinder(_:)))
        default:
            return nil
        }
    }

    private func item(
        _ identifier: NSToolbarItem.Identifier, _ label: String, _ symbol: String, _ action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    // MARK: - Window

    func windowWillClose(_ notification: Notification) {
        noticeTimer?.invalidate()
        onClose?(self)
    }
}

/// Accepts drawings dragged onto the window, whether or not one is open.
final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?
    private var isTarget = false {
        didSet { if isTarget != oldValue { needsDisplay = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isTarget = !drawings(in: sender).isEmpty
        return isTarget ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { isTarget = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTarget = false
        let urls = drawings(in: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isTarget else { return }
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 8, yRadius: 8)
        border.lineWidth = 3
        NSColor.controlAccentColor.setStroke()
        border.stroke()
    }

    private func drawings(in sender: NSDraggingInfo) -> [URL] {
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return objects.filter { ExcalidrawFile.extensions.contains($0.pathExtension.lowercased()) }
    }
}

enum ExcalidrawFile {
    static let extensions = ["excalidraw", "excalidrawlib"]
}
