import AppKit

// The extensions have to live inside an app bundle, and macOS only registers
// them once that app has been seen in a normal Applications folder. This app's
// only job is to be that container, and to say so if someone opens it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let text = """
        Excalidraw QuickLook is installed.

        Select an .excalidraw file in Finder and press space to preview it.
        Finder icons show the drawing too.

        This window does nothing else — the previews are provided by two
        extensions inside this app. They stop working if you move or delete it.
        """

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.frame = CGRect(x: 24, y: 24, width: 412, height: 180)

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 228),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Excalidraw QuickLook"
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.activate(ignoringOtherApps: true)
application.run()
