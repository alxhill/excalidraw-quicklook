import AppKit
import UniformTypeIdentifiers

/// The app is both the container the QuickLook extensions have to live inside
/// and a read-only viewer for the files they preview.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var windows: [ViewerWindow] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        Fonts.registerBundledFonts(in: Bundle.main.resourceURL?.appendingPathComponent("Fonts"))
        NSApp.mainMenu = MainMenu.build(recentDelegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Handy when working on the app: ExcalidrawQuickLook drawing.excalidraw
        open(CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }.map(URL.init(fileURLWithPath:)))

        // Files opened from Finder arrive in their own callback, which may not
        // have run yet, so decide about an empty window one turn later.
        DispatchQueue.main.async { [self] in
            if windows.isEmpty { showWindow(for: nil) }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        open(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if windows.isEmpty { showWindow(for: nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Opening

    private func open(_ urls: [URL]) {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            showWindow(for: url)
        }
    }

    private func showWindow(for url: URL?) {
        if let url, let existing = windows.first(where: { $0.fileURL == url }) {
            existing.window?.makeKeyAndOrderFront(nil)
            existing.reload(nil)
            return
        }

        // An empty window is a placeholder, so open into it rather than beside it.
        let window = windows.first(where: { $0.fileURL == nil }) ?? makeWindow()
        if let url { window.open(url) }
        window.showWindow(nil)
        window.window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> ViewerWindow {
        let window = ViewerWindow()
        // The array is the only thing holding the controller, so let
        // windowWillClose: return before it goes away.
        window.onClose = { [weak self] closed in
            DispatchQueue.main.async { self?.windows.removeAll { $0 === closed } }
        }
        window.onOpenFiles = { [weak self] urls in self?.open(urls) }
        windows.append(window)
        return window
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let types = ExcalidrawFile.extensions.compactMap { UTType(filenameExtension: $0) }
        if !types.isEmpty { panel.allowedContentTypes = types }
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open([url])
    }

    // MARK: - Open Recent

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let recents = NSDocumentController.shared.recentDocumentURLs
        for url in recents {
            let item = menu.addItem(
                withTitle: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = url
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = CGSize(width: 16, height: 16)
        }
        if recents.isEmpty {
            menu.addItem(withTitle: "No Recent Files", action: nil, keyEquivalent: "").isEnabled = false
            return
        }
        menu.addItem(.separator())
        let clear = menu.addItem(
            withTitle: "Clear Menu",
            action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        clear.target = NSDocumentController.shared
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.activate(ignoringOtherApps: true)
application.run()
