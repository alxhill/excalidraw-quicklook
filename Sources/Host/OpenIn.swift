import AppKit
import UniformTypeIdentifiers

/// Handing the file to something that can edit it — the one thing a read-only
/// viewer owes the person looking at it.
enum OpenIn {
    /// VS Code and the builds that pretend to be it, in preference order.
    /// The last one is Cursor, which ships under a todesktop identifier.
    private static let editorIdentifiers = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.visualstudio.code.oss",
        "com.todesktop.230313mzl4w4u92",
    ]

    /// The Excalidraw desktop app has shipped under more than one identifier,
    /// so fall back to anything installed that calls itself Excalidraw.
    private static let excalidrawIdentifiers = [
        "com.excalidraw.excalidraw",
        "com.excalidraw.desktop",
        "excalidraw.desktop",
    ]

    /// Looked up once: an app appearing mid-session is not worth a disk hit on
    /// every menu validation.
    static let editor: URL? = editorIdentifiers.lazy.compactMap(application(withIdentifier:)).first

    static let excalidrawApp: URL? = {
        if let known = excalidrawIdentifiers.lazy.compactMap(application(withIdentifier:)).first {
            return known
        }
        return installedExcalidrawLikeApp()
    }()

    enum ExcalidrawTarget {
        case app(URL)
        /// The website, with the drawing loaded into it.
        case website
        /// The website, but the drawing had to be left behind.
        case websiteWithoutDrawing
    }

    /// The desktop editor if it is installed, excalidraw.com otherwise.
    @discardableResult
    static func excalidraw(_ file: URL) -> ExcalidrawTarget {
        if let app = excalidrawApp {
            open(file, with: app)
            return .app(app)
        }
        if let loaded = websiteURL(loadingSceneAt: file) {
            NSWorkspace.shared.open(loaded)
            return .website
        }
        NSWorkspace.shared.open(website)
        return .websiteWithoutDrawing
    }

    private static let website = URL(string: "https://excalidraw.com")!

    /// A local path means nothing to the website, but its `#url=` loader
    /// fetches whatever it is handed and a `data:` URL is something the browser
    /// resolves on its own — so the drawing rides along inside the link and is
    /// never uploaded anywhere. Excalidraw then rewrites the address bar, so
    /// the link does not linger.
    ///
    /// Two cases get nothing: `.excalidrawlib`, because the library importer
    /// only accepts URLs on Excalidraw's own allowlist, and anything big enough
    /// that a link carrying it looks unwise.
    private static func websiteURL(loadingSceneAt file: URL) -> URL? {
        guard file.pathExtension.lowercased() != "excalidrawlib",
              let data = try? Data(contentsOf: file),
              data.count <= inlineLimit else { return nil }

        let inline = "data:application/json;base64,\(data.base64EncodedString())"
        guard let encoded = inline.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { return nil }
        return URL(string: "https://excalidraw.com/#url=\(encoded)")
    }

    private static let inlineLimit = 1_000_000

    static func open(_ file: URL, with application: URL) {
        NSWorkspace.shared.open(
            [file], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()
        )
    }

    static func reveal(_ file: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    static func name(of application: URL) -> String {
        FileManager.default.displayName(atPath: application.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private static func application(withIdentifier identifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }

    /// Any registered handler for the drawing type whose identifier mentions
    /// Excalidraw — and never this app, which would open a second window.
    private static func installedExcalidrawLikeApp() -> URL? {
        guard let type = UTType(filenameExtension: "excalidraw") else { return nil }
        let ours = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.urlsForApplications(toOpen: type).first { candidate in
            guard let identifier = Bundle(url: candidate)?.bundleIdentifier,
                  identifier != ours else { return false }
            return identifier.lowercased().contains("excalidraw")
        }
    }
}
