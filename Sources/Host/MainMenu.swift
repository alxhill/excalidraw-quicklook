import AppKit

// A nib-less app gets no menu bar unless it builds one. Every item here is
// targetless on purpose: AppKit sends the action down the responder chain, so
// the key window's ViewerWindow answers the document actions and the app
// delegate answers the rest — and an item whose action nobody implements right
// now greys itself out.
enum MainMenu {
    static func build(recentDelegate: NSMenuDelegate) -> NSMenu {
        let name = "Excalidraw QuickLook"
        let main = NSMenu()

        let app = submenu(name, in: main)
        add("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: app)
        app.addItem(.separator())
        add("Hide \(name)", #selector(NSApplication.hide(_:)), "h", to: app)
        add(
            "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
            modifiers: [.command, .option], to: app
        )
        add("Show All", #selector(NSApplication.unhideAllApplications(_:)), to: app)
        app.addItem(.separator())
        add("Quit \(name)", #selector(NSApplication.terminate(_:)), "q", to: app)

        let file = submenu("File", in: main)
        add("Open…", #selector(AppDelegate.openDocument(_:)), "o", to: file)
        let recent = add("Open Recent", nil, to: file)
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = recentDelegate
        recent.submenu = recentMenu
        file.addItem(.separator())
        add("Reload", #selector(ViewerWindow.reload(_:)), "r", to: file)
        file.addItem(.separator())
        // Named after what is actually installed, rather than offering to open
        // the drawing in something that is not there.
        let excalidraw = OpenIn.excalidrawApp.map(OpenIn.name(of:)) ?? "Excalidraw"
        add("Open in \(excalidraw)", #selector(ViewerWindow.openInExcalidraw(_:)), "E", to: file)
        let editor = OpenIn.editor.map(OpenIn.name(of:)) ?? "VS Code"
        add("Open in \(editor)", #selector(ViewerWindow.openInEditor(_:)), "B", to: file)
        add("Reveal in Finder", #selector(ViewerWindow.revealInFinder(_:)), "R", to: file)
        file.addItem(.separator())
        add("Close", #selector(NSWindow.performClose(_:)), "w", to: file)

        let edit = submenu("Edit", in: main)
        add("Copy as PNG", #selector(ViewerWindow.copy(_:)), "c", to: edit)
        add(
            "Copy File Path", #selector(ViewerWindow.copyFilePath(_:)), "c",
            modifiers: [.command, .option], to: edit
        )

        let view = submenu("View", in: main)
        add("Zoom In", #selector(ViewerWindow.zoomInCanvas(_:)), "+", to: view)
        add("Zoom Out", #selector(ViewerWindow.zoomOutCanvas(_:)), "-", to: view)
        add("Actual Size", #selector(ViewerWindow.zoomToActualSize(_:)), "1", to: view)
        add("Zoom to Fit", #selector(ViewerWindow.zoomToFit(_:)), "0", to: view)

        let window = submenu("Window", in: main)
        add("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", to: window)
        add("Zoom", #selector(NSWindow.performZoom(_:)), to: window)
        window.addItem(.separator())
        add("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), to: window)
        NSApp.windowsMenu = window

        return main
    }

    @discardableResult
    private static func add(
        _ title: String,
        _ action: Selector?,
        _ key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        to menu: NSMenu
    ) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func submenu(_ title: String, in main: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }
}
