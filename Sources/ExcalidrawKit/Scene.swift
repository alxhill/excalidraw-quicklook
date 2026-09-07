import CoreGraphics
import Foundation

// The subset of the .excalidraw document model that affects rendering.
// Everything is optional-with-default: files written by older versions of
// Excalidraw omit fields that newer ones always emit, and vice versa.

struct Roundness {
    let type: Int
    let value: Double?
}

struct EmbeddedFile {
    let mimeType: String
    let dataURL: String
}

struct Element {
    var id: String
    var type: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var angle: Double
    var strokeColor: String
    var backgroundColor: String
    var fillStyle: String
    var strokeWidth: Double
    var strokeStyle: String
    var roughness: Double
    var opacity: Double
    var seed: Int
    var roundness: Roundness?
    var isDeleted: Bool
    var frameId: String?

    // text
    var text: String?
    var fontSize: Double?
    var fontFamily: Int?
    var textAlign: String?
    var verticalAlign: String?
    var lineHeight: Double?
    var containerId: String?

    // line / arrow / freedraw
    var points: [CGPoint]?
    var startArrowhead: String?
    var endArrowhead: String?
    var polygon: Bool

    // image
    var fileId: String?
    var scale: [Double]?

    // frame
    var name: String?
}

struct Scene {
    var elements: [Element]
    var backgroundColor: String
    var files: [String: EmbeddedFile]
}

enum SceneParseError: Error, LocalizedError {
    case notJSON
    case notAnExcalidrawFile
    case empty

    var errorDescription: String? {
        switch self {
        case .notJSON: return "Not valid JSON."
        case .notAnExcalidrawFile: return "Not an Excalidraw document."
        case .empty: return "This drawing is empty."
        }
    }
}

// Hand-rolled traversal of the parsed JSON rather than Codable: the element
// schema is a union of ~9 shapes and tolerating unknown/missing/null fields
// matters more here than type safety at the boundary.
enum SceneParser {
    static func parse(data: Data) throws -> Scene {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SceneParseError.notJSON
        }

        var rawElements = root["elements"] as? [[String: Any]]

        // .excalidrawlib: flatten every library item onto one canvas.
        if rawElements == nil, let items = root["libraryItems"] as? [[String: Any]] {
            rawElements = items.flatMap { $0["elements"] as? [[String: Any]] ?? [] }
        }
        // A bare array of elements is what "copy as JSON" produces.
        if rawElements == nil, let bare = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            rawElements = bare
        }

        guard let rawElements else { throw SceneParseError.notAnExcalidrawFile }

        let elements = rawElements.compactMap(element(from:)).filter { !$0.isDeleted }
        guard !elements.isEmpty else { throw SceneParseError.empty }

        var files: [String: EmbeddedFile] = [:]
        if let rawFiles = root["files"] as? [String: Any] {
            for (key, value) in rawFiles {
                guard let entry = value as? [String: Any],
                      let dataURL = entry["dataURL"] as? String else { continue }
                files[key] = EmbeddedFile(
                    mimeType: entry["mimeType"] as? String ?? "application/octet-stream",
                    dataURL: dataURL
                )
            }
        }

        let appState = root["appState"] as? [String: Any]
        let background = appState?["viewBackgroundColor"] as? String ?? "#ffffff"

        return Scene(elements: elements, backgroundColor: background, files: files)
    }

    private static func element(from raw: [String: Any]) -> Element? {
        guard let type = raw["type"] as? String else { return nil }

        var points: [CGPoint]?
        if let rawPoints = raw["points"] as? [[Any]] {
            points = rawPoints.compactMap { pair in
                guard pair.count >= 2,
                      let px = num(pair[0]), let py = num(pair[1]) else { return nil }
                return CGPoint(x: px, y: py)
            }
        }

        var roundness: Roundness?
        if let rawRoundness = raw["roundness"] as? [String: Any],
           let kind = num(rawRoundness["type"]) {
            roundness = Roundness(type: Int(kind), value: num(rawRoundness["value"]))
        }

        return Element(
            id: raw["id"] as? String ?? UUID().uuidString,
            type: type,
            x: num(raw["x"]) ?? 0,
            y: num(raw["y"]) ?? 0,
            width: num(raw["width"]) ?? 0,
            height: num(raw["height"]) ?? 0,
            angle: num(raw["angle"]) ?? 0,
            strokeColor: raw["strokeColor"] as? String ?? "#1e1e1e",
            backgroundColor: raw["backgroundColor"] as? String ?? "transparent",
            fillStyle: raw["fillStyle"] as? String ?? "solid",
            strokeWidth: num(raw["strokeWidth"]) ?? 1,
            strokeStyle: raw["strokeStyle"] as? String ?? "solid",
            roughness: num(raw["roughness"]) ?? 1,
            opacity: num(raw["opacity"]) ?? 100,
            seed: Int(num(raw["seed"]) ?? 1),
            roundness: roundness,
            isDeleted: raw["isDeleted"] as? Bool ?? false,
            frameId: raw["frameId"] as? String,
            text: raw["text"] as? String ?? raw["originalText"] as? String,
            fontSize: num(raw["fontSize"]),
            fontFamily: num(raw["fontFamily"]).map(Int.init),
            textAlign: raw["textAlign"] as? String,
            verticalAlign: raw["verticalAlign"] as? String,
            lineHeight: num(raw["lineHeight"]),
            containerId: raw["containerId"] as? String,
            points: points,
            startArrowhead: raw["startArrowhead"] as? String,
            endArrowhead: raw["endArrowhead"] as? String,
            polygon: raw["polygon"] as? Bool ?? false,
            fileId: raw["fileId"] as? String,
            scale: (raw["scale"] as? [Any])?.compactMap(num),
            name: raw["name"] as? String
        )
    }

    private static func num(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}
