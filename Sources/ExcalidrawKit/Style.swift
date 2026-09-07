import CoreGraphics
import CoreText
import Foundation

enum Colors {
    static func parse(_ raw: String) -> CGColor? {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if value.isEmpty || value == "transparent" || value == "none" { return nil }

        if value.hasPrefix("#") {
            return hex(String(value.dropFirst()))
        }
        if value.hasPrefix("rgb") {
            let numbers = value
                .drop(while: { $0 != "(" })
                .dropFirst()
                .prefix(while: { $0 != ")" })
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                .compactMap { Double($0) }
            guard numbers.count >= 3 else { return nil }
            let alpha = numbers.count > 3 ? (numbers[3] > 1 ? numbers[3] / 100 : numbers[3]) : 1
            return color(numbers[0] / 255, numbers[1] / 255, numbers[2] / 255, alpha)
        }
        return named[value]
    }

    private static func hex(_ digits: String) -> CGColor? {
        let chars = Array(digits)
        func component(_ index: Int, short: Bool) -> Double? {
            if short {
                guard index < chars.count, let v = Int(String(chars[index]), radix: 16) else { return nil }
                return Double(v * 17) / 255
            }
            let start = index * 2
            guard start + 1 < chars.count,
                  let v = Int(String(chars[start...(start + 1)]), radix: 16) else { return nil }
            return Double(v) / 255
        }

        switch chars.count {
        case 3, 4:
            guard let r = component(0, short: true),
                  let g = component(1, short: true),
                  let b = component(2, short: true) else { return nil }
            return color(r, g, b, chars.count == 4 ? (component(3, short: true) ?? 1) : 1)
        case 6, 8:
            guard let r = component(0, short: false),
                  let g = component(1, short: false),
                  let b = component(2, short: false) else { return nil }
            return color(r, g, b, chars.count == 8 ? (component(3, short: false) ?? 1) : 1)
        default:
            return nil
        }
    }

    private static func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static let named: [String: CGColor] = [
        "white": color(1, 1, 1, 1),
        "black": color(0, 0, 0, 1),
        "red": color(1, 0, 0, 1),
        "green": color(0, 0.5, 0, 1),
        "blue": color(0, 0, 1, 1),
        "yellow": color(1, 1, 0, 1),
        "gray": color(0.5, 0.5, 0.5, 1),
        "grey": color(0.5, 0.5, 0.5, 1),
    ]
}

enum Fonts {
    /// Excalidraw's FONT_FAMILY ids. The real fonts ship as woff2, which
    /// CoreText cannot load, so each maps to the closest installed face —
    /// unless a matching ttf/otf was dropped into the bundle's Fonts folder
    /// (see `make fonts`), which takes priority.
    private static let substitutes: [Int: (preferred: String, fallback: [String])] = [
        1: ("Virgil", ["Comic Sans MS", "Chalkboard SE", "Bradley Hand"]),          // Virgil
        2: ("Helvetica", ["Helvetica Neue", "Helvetica"]),                          // Helvetica
        3: ("Cascadia Code", ["Menlo", "Monaco"]),                                  // Cascadia
        4: ("Assistant", ["Helvetica Neue", "Helvetica"]),                          // Assistant
        5: ("Excalifont", ["Comic Sans MS", "Chalkboard SE", "Bradley Hand"]),      // Excalifont
        6: ("Nunito", ["Helvetica Neue", "Helvetica"]),                             // Nunito
        7: ("Lilita One", ["Impact", "Helvetica Neue Bold", "Helvetica"]),          // Lilita One
        8: ("Comic Shanns", ["Comic Sans MS", "Menlo"]),                            // Comic Shanns
    ]

    private static var cache: [Int: CTFont] = [:]
    private static var registered = false

    /// Registers bundled font files process-wide. Safe to call repeatedly.
    static func registerBundledFonts(in directory: URL?) {
        guard !registered else { return }
        registered = true
        guard let directory,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
              ) else { return }
        let fontURLs = contents.filter { ["ttf", "otf", "ttc"].contains($0.pathExtension.lowercased()) }
        guard !fontURLs.isEmpty else { return }
        CTFontManagerRegisterFontURLs(fontURLs as CFArray, .process, false, nil)
    }

    static func font(family: Int?, size: Double) -> CTFont {
        let key = family ?? 5
        let base = cache[key] ?? resolve(family: key)
        cache[key] = base
        return CTFontCreateCopyWithAttributes(base, size, nil, nil)
    }

    private static func resolve(family: Int) -> CTFont {
        let entry = substitutes[family] ?? substitutes[5]!
        for name in [entry.preferred] + entry.fallback {
            if let font = exactFont(named: name) { return font }
        }
        return CTFontCreateWithName("Helvetica" as CFString, 16, nil)
    }

    /// CTFontCreateWithName substitutes silently, so confirm we got the family
    /// we asked for before accepting it.
    private static func exactFont(named name: String) -> CTFont? {
        let font = CTFontCreateWithName(name as CFString, 16, nil)
        let resolved = CTFontCopyFamilyName(font) as String
        let wanted = name.replacingOccurrences(of: " Bold", with: "")
        return resolved.compare(wanted, options: .caseInsensitive) == .orderedSame ? font : nil
    }
}
