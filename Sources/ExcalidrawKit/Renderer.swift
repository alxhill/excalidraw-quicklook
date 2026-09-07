import CoreGraphics
import CoreText
import Foundation
import ImageIO

struct RenderOptions {
    /// The rendered image is fitted inside this box, in points.
    var maximumSize: CGSize
    /// Device pixels per point.
    var scale: CGFloat = 2
    var padding: CGFloat = 12
    /// Small drawings are allowed to scale up to this, so a three-box sketch
    /// still fills a thumbnail instead of sitting in the middle of it.
    var maximumZoom: CGFloat = 3

    init(maximumSize: CGSize, scale: CGFloat = 2, padding: CGFloat = 12, maximumZoom: CGFloat = 3) {
        self.maximumSize = maximumSize
        self.scale = scale
        self.padding = padding
        self.maximumZoom = maximumZoom
    }
}

enum SceneRenderer {
    /// The drawing at 1:1 plus padding, in points.
    static func contentSize(of scene: Scene, padding: CGFloat) -> CGSize {
        let bounds = self.bounds(of: scene)
        return CGSize(
            width: max(bounds.width + padding * 2, 1),
            height: max(bounds.height + padding * 2, 1)
        )
    }

    /// Draws the scene fitted and centred inside `rect` of an existing y-up
    /// context. Used directly by the preview, which draws at whatever zoom the
    /// scroll view is at so text and strokes stay crisp, and via `render`
    /// below for thumbnails.
    static func draw(
        _ scene: Scene,
        in ctx: CGContext,
        fitting rect: CGRect,
        padding: CGFloat = 12,
        maximumZoom: CGFloat = .greatestFiniteMagnitude
    ) {
        let bounds = self.bounds(of: scene)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let available = CGSize(
            width: max(rect.width - padding * 2, 1),
            height: max(rect.height - padding * 2, 1)
        )
        let zoom = min(
            maximumZoom,
            min(available.width / bounds.width, available.height / bounds.height)
        )

        ctx.saveGState()
        defer { ctx.restoreGState() }

        // Flip into Excalidraw's y-down space within the target rect.
        ctx.translateBy(x: rect.minX, y: rect.minY + rect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(
            x: (rect.width - bounds.width * zoom) / 2,
            y: (rect.height - bounds.height * zoom) / 2
        )
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.interpolationQuality = .high

        let labels = Dictionary(
            scene.elements
                .filter { $0.type == "text" }
                .compactMap { element in element.containerId.map { ($0, element) } },
            uniquingKeysWith: { first, _ in first }
        )

        // The clip box is in scene coordinates now, so zoomed-in scrolling only
        // pays for the elements actually on screen.
        let visible = ctx.boundingBoxOfClipPath.insetBy(dx: -64, dy: -64)

        for element in scene.elements {
            if let box = self.bounds(of: element), !box.intersects(visible) { continue }
            draw(element, in: ctx, scene: scene, labels: labels)
        }
    }

    static func render(_ scene: Scene, options: RenderOptions) -> CGImage? {
        let bounds = self.bounds(of: scene)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let available = CGSize(
            width: max(options.maximumSize.width - options.padding * 2, 1),
            height: max(options.maximumSize.height - options.padding * 2, 1)
        )
        let zoom = min(
            options.maximumZoom,
            min(available.width / bounds.width, available.height / bounds.height)
        )

        let pointSize = CGSize(
            width: bounds.width * zoom + options.padding * 2,
            height: bounds.height * zoom + options.padding * 2
        )
        let pixelSize = CGSize(
            width: max(round(pointSize.width * options.scale), 1),
            height: max(round(pointSize.height * options.scale), 1)
        )

        guard let ctx = CGContext(
            data: nil,
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(Colors.parse(scene.backgroundColor) ?? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: pixelSize))

        ctx.scaleBy(x: options.scale, y: options.scale)
        draw(
            scene, in: ctx, fitting: CGRect(origin: .zero, size: pointSize),
            padding: options.padding, maximumZoom: options.maximumZoom
        )

        return ctx.makeImage()
    }

    // MARK: - Bounds

    static func bounds(of scene: Scene) -> CGRect {
        var result: CGRect?
        for element in scene.elements {
            guard let rect = self.bounds(of: element) else { continue }
            result = result.map { $0.union(rect) } ?? rect
        }
        // Room for the widest stroke plus frame name labels.
        return (result ?? .zero).insetBy(dx: -6, dy: -6)
    }

    private static func bounds(of element: Element) -> CGRect? {
        var rect: CGRect
        if let points = element.points, !points.isEmpty {
            var minX = Double.greatestFiniteMagnitude, minY = Double.greatestFiniteMagnitude
            var maxX = -Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
            for point in points {
                minX = min(minX, point.x); maxX = max(maxX, point.x)
                minY = min(minY, point.y); maxY = max(maxY, point.y)
            }
            rect = CGRect(
                x: element.x + minX, y: element.y + minY,
                width: maxX - minX, height: maxY - minY
            )
        } else {
            rect = CGRect(x: element.x, y: element.y, width: element.width, height: element.height)
        }
        rect = rect.standardized
        if rect.width == 0 && rect.height == 0 { return nil }
        if element.type == "frame" || element.type == "magicframe" {
            rect = rect.insetBy(dx: 0, dy: -20)
        }
        guard element.angle != 0 else { return rect }

        // Rotated elements store their unrotated box, so expand to the rotated hull.
        let center = CGPoint(x: element.x + element.width / 2, y: element.y + element.height / 2)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ].map { rotate($0, around: center, by: element.angle) }
        return hull(of: corners)
    }

    private static func rotate(_ point: CGPoint, around center: CGPoint, by angle: Double) -> CGPoint {
        let dx = point.x - center.x, dy = point.y - center.y
        return CGPoint(
            x: center.x + dx * cos(angle) - dy * sin(angle),
            y: center.y + dx * sin(angle) + dy * cos(angle)
        )
    }

    private static func hull(of points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(
            x: xs.min()!, y: ys.min()!,
            width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!
        )
    }

    // MARK: - Elements

    private static func draw(
        _ element: Element, in ctx: CGContext, scene: Scene, labels: [String: Element]
    ) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.setAlpha(CGFloat(max(0, min(100, element.opacity)) / 100))

        if element.angle != 0 {
            let center = CGPoint(x: element.x + element.width / 2, y: element.y + element.height / 2)
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: element.angle)
            ctx.translateBy(x: -center.x, y: -center.y)
        }

        switch element.type {
        case "rectangle", "diamond", "ellipse":
            drawShape(element, in: ctx)
        case "line", "arrow":
            drawLinear(element, in: ctx, label: labels[element.id])
        case "freedraw":
            drawFreedraw(element, in: ctx)
        case "text":
            drawText(element, in: ctx)
        case "image":
            drawImage(element, in: ctx, scene: scene)
        case "frame", "magicframe":
            drawFrame(element, in: ctx)
        case "embeddable", "iframe":
            drawPlaceholder(element, in: ctx)
        default:
            break
        }
    }

    // MARK: - Shapes

    private static func cornerRadius(_ element: Element) -> CGFloat {
        guard let roundness = element.roundness else { return 0 }
        let shortest = min(abs(element.width), abs(element.height))
        if roundness.type == 2 { return shortest * 0.25 }
        let fixed = roundness.value ?? 32
        let cutoff = fixed / 0.25
        return shortest <= cutoff ? shortest * 0.25 : fixed
    }

    private static func drawShape(_ element: Element, in ctx: CGContext) {
        let rect = CGRect(x: element.x, y: element.y, width: element.width, height: element.height)
            .standardized
        let radius = cornerRadius(element)
        let sketchy = element.roughness > 0
        var rough = Rough(seed: element.seed, options: roughOptions(element))

        let fillPath: CGPath
        let strokePath: CGPath

        switch element.type {
        case "ellipse":
            let samples = ellipsePoints(in: rect, count: 16)
            fillPath = CGPath(ellipseIn: rect, transform: nil)
            strokePath = sketchy
                ? rough.curve(samples, closed: true, jitter: 1.5 * sqrt(element.roughness))
                : fillPath
        case "diamond":
            let points = [
                CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.midX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.midY),
            ]
            fillPath = closedPath(points)
            strokePath = sketchy ? rough.polyline(points, closed: true) : fillPath
        default:
            if radius > 0 {
                fillPath = CGPath(
                    roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil
                )
                strokePath = sketchy
                    ? rough.curve(
                        roundedRectPoints(rect, radius: radius), closed: true,
                        jitter: 1.2 * sqrt(element.roughness)
                      )
                    : fillPath
            } else {
                let points = [
                    CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
                ]
                fillPath = closedPath(points)
                strokePath = sketchy ? rough.polyline(points, closed: true) : fillPath
            }
        }

        fill(fillPath, element: element, in: ctx)
        stroke(strokePath, element: element, in: ctx)
    }

    private static func closedPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    private static func ellipsePoints(in rect: CGRect, count: Int) -> [CGPoint] {
        (0..<count).map { index in
            let theta = Double(index) / Double(count) * 2 * .pi
            return CGPoint(
                x: rect.midX + rect.width / 2 * cos(theta),
                y: rect.midY + rect.height / 2 * sin(theta)
            )
        }
    }

    /// Samples the rounded-rect outline at even arc length. Even spacing is
    /// what keeps the Catmull-Rom fit from overshooting at the corners.
    private static func roundedRectPoints(_ rect: CGRect, radius: CGFloat) -> [CGPoint] {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let horizontal = max(rect.width - 2 * r, 0)
        let vertical = max(rect.height - 2 * r, 0)

        func edge(_ from: CGPoint, _ to: CGPoint) -> (CGFloat, (CGFloat) -> CGPoint) {
            (hypot(to.x - from.x, to.y - from.y), { t in
                CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            })
        }
        func arc(_ center: CGPoint, _ start: CGFloat) -> (CGFloat, (CGFloat) -> CGPoint) {
            (r * .pi / 2, { t in
                let theta = start + t * .pi / 2
                return CGPoint(x: center.x + r * cos(theta), y: center.y + r * sin(theta))
            })
        }

        let segments: [(CGFloat, (CGFloat) -> CGPoint)] = [
            edge(CGPoint(x: rect.minX + r, y: rect.minY), CGPoint(x: rect.maxX - r, y: rect.minY)),
            arc(CGPoint(x: rect.maxX - r, y: rect.minY + r), -.pi / 2),
            edge(CGPoint(x: rect.maxX, y: rect.minY + r), CGPoint(x: rect.maxX, y: rect.maxY - r)),
            arc(CGPoint(x: rect.maxX - r, y: rect.maxY - r), 0),
            edge(CGPoint(x: rect.maxX - r, y: rect.maxY), CGPoint(x: rect.minX + r, y: rect.maxY)),
            arc(CGPoint(x: rect.minX + r, y: rect.maxY - r), .pi / 2),
            edge(CGPoint(x: rect.minX, y: rect.maxY - r), CGPoint(x: rect.minX, y: rect.minY + r)),
            arc(CGPoint(x: rect.minX + r, y: rect.minY + r), .pi),
        ]

        let perimeter = 2 * (horizontal + vertical) + 2 * .pi * r
        guard perimeter > 0 else { return [] }
        let count = max(20, min(56, Int(perimeter / 16)))
        let step = perimeter / CGFloat(count)

        var points: [CGPoint] = []
        var distance: CGFloat = 0
        var index = 0
        var consumed: CGFloat = 0
        while points.count < count && index < segments.count {
            let (length, at) = segments[index]
            if length <= 0 || distance > consumed + length {
                consumed += length
                index += 1
                continue
            }
            points.append(at((distance - consumed) / length))
            distance += step
        }
        return points
    }

    // MARK: - Linear

    private static func drawLinear(_ element: Element, in ctx: CGContext, label: Element?) {
        guard let raw = element.points, raw.count >= 2 else { return }
        let points = raw.map { CGPoint(x: element.x + $0.x, y: element.y + $0.y) }
        let curved = element.roundness != nil && points.count > 2
        let closed = element.polygon
        var rough = Rough(seed: element.seed, options: roughOptions(element))

        let exact = CGMutablePath()
        if curved {
            Curves.append(points, closed: closed, to: exact)
        } else {
            exact.addLines(between: points)
            if closed { exact.closeSubpath() }
        }

        if element.polygon || Colors.parse(element.backgroundColor) != nil {
            fill(exact, element: element, in: ctx)
        }

        let path: CGPath
        if element.roughness > 0 {
            path = curved
                ? rough.curve(points, closed: closed, jitter: 1.2 * sqrt(element.roughness))
                : rough.polyline(points, closed: closed)
        } else {
            path = exact
        }
        if let label, label.width > 0, label.height > 0 {
            // Excalidraw breaks the line where a bound label sits rather than
            // drawing through it.
            let hole = CGRect(x: label.x, y: label.y, width: label.width, height: label.height)
                .insetBy(dx: -4, dy: -2)
            let clip = CGMutablePath()
            clip.addRect(path.boundingBoxOfPath.insetBy(dx: -32, dy: -32))
            clip.addRect(hole)
            ctx.saveGState()
            ctx.addPath(clip)
            ctx.clip(using: .evenOdd)
            stroke(path, element: element, in: ctx)
            ctx.restoreGState()
        } else {
            stroke(path, element: element, in: ctx)
        }

        guard element.type == "arrow" else { return }
        if let head = element.startArrowhead {
            drawArrowhead(head, tip: points[0], from: points[1], element: element, in: ctx)
        }
        if let head = element.endArrowhead {
            drawArrowhead(
                head, tip: points[points.count - 1], from: points[points.count - 2],
                element: element, in: ctx
            )
        }
    }

    private static func drawArrowhead(
        _ kind: String, tip: CGPoint, from previous: CGPoint, element: Element, in ctx: CGContext
    ) {
        let dx = tip.x - previous.x, dy = tip.y - previous.y
        let distance = hypot(dx, dy)
        guard distance > 0.01 else { return }
        let ux = dx / distance, uy = dy / distance
        let color = Colors.parse(element.strokeColor) ?? CGColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1)

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(element.strokeWidth)

        switch kind {
        case "arrow":
            let length = min(25 + element.strokeWidth * 2, distance / 2)
            let angle = 20.0 * .pi / 180
            let base = CGPoint(x: tip.x - ux * length, y: tip.y - uy * length)
            for sign in [-1.0, 1.0] {
                let barb = rotate(base, around: tip, by: sign * angle)
                ctx.move(to: tip)
                ctx.addLine(to: barb)
            }
            ctx.strokePath()
        case "bar":
            let half = 8 + element.strokeWidth
            ctx.move(to: CGPoint(x: tip.x - uy * half, y: tip.y + ux * half))
            ctx.addLine(to: CGPoint(x: tip.x + uy * half, y: tip.y - ux * half))
            ctx.strokePath()
        case "dot", "circle", "circle_outline":
            let radius = 4 + element.strokeWidth
            let rect = CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2)
            ctx.addEllipse(in: rect)
            kind == "circle_outline" ? ctx.strokePath() : ctx.fillPath()
        case "diamond", "diamond_outline":
            let size = 10 + element.strokeWidth
            let back = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
            let mid = CGPoint(x: tip.x - ux * size / 2, y: tip.y - uy * size / 2)
            let half = size / 2.5
            ctx.move(to: tip)
            ctx.addLine(to: CGPoint(x: mid.x - uy * half, y: mid.y + ux * half))
            ctx.addLine(to: back)
            ctx.addLine(to: CGPoint(x: mid.x + uy * half, y: mid.y - ux * half))
            ctx.closePath()
            kind == "diamond_outline" ? ctx.strokePath() : ctx.fillPath()
        default:  // triangle, triangle_outline
            let length = min(15 + element.strokeWidth * 2, distance / 2)
            let base = CGPoint(x: tip.x - ux * length, y: tip.y - uy * length)
            let half = length * 0.4
            ctx.move(to: tip)
            ctx.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
            ctx.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
            ctx.closePath()
            kind == "triangle_outline" ? ctx.strokePath() : ctx.fillPath()
        }
    }

    private static func drawFreedraw(_ element: Element, in ctx: CGContext) {
        guard let raw = element.points, raw.count >= 2 else { return }
        let points = raw.map { CGPoint(x: element.x + $0.x, y: element.y + $0.y) }
        let path = CGMutablePath()
        Curves.append(points, closed: false, to: path)
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(Colors.parse(element.strokeColor) ?? CGColor(gray: 0.1, alpha: 1))
        // Excalidraw runs freedraw through perfect-freehand at size 4.25x the
        // stroke width, tapered by pressure; a round-capped stroke at roughly
        // half that reads the same at preview scale.
        ctx.setLineWidth(element.strokeWidth * 2.25)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Text

    private static func drawText(_ element: Element, in ctx: CGContext) {
        guard let text = element.text, !text.isEmpty else { return }
        let fontSize = element.fontSize ?? 20
        let font = Fonts.font(family: element.fontFamily, size: fontSize)
        let color = Colors.parse(element.strokeColor) ?? CGColor(gray: 0.1, alpha: 1)
        let lineHeight = fontSize * (element.lineHeight ?? 1.25)
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let baselineInLine = (lineHeight - (ascent + descent)) / 2 + ascent

        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            guard !line.isEmpty else { continue }
            let attributed = NSAttributedString(string: line, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: color,
            ])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)

            let x: CGFloat
            switch element.textAlign {
            case "center": x = element.x + (element.width - width) / 2
            case "right": x = element.x + element.width - width
            default: x = element.x
            }

            ctx.textPosition = CGPoint(x: x, y: element.y + CGFloat(index) * lineHeight + baselineInLine)
            CTLineDraw(ctLine, ctx)
        }
    }

    // MARK: - Images and frames

    private static func drawImage(_ element: Element, in ctx: CGContext, scene: Scene) {
        let rect = CGRect(x: element.x, y: element.y, width: element.width, height: element.height)
            .standardized
        guard let fileId = element.fileId,
              let file = scene.files[fileId],
              let image = decodeDataURL(file.dataURL) else {
            drawPlaceholder(element, in: ctx)
            return
        }

        ctx.saveGState()
        // The context is flipped relative to CGImage's origin, and Excalidraw
        // records mirroring as a negative scale component.
        let flipX = (element.scale?.first ?? 1) < 0
        let flipY = (element.scale?.count ?? 0) > 1 && element.scale![1] < 0
        ctx.translateBy(x: rect.midX, y: rect.midY)
        ctx.scaleBy(x: flipX ? -1 : 1, y: flipY ? 1 : -1)
        ctx.translateBy(x: -rect.midX, y: -rect.midY)
        ctx.draw(image, in: rect)
        ctx.restoreGState()
    }

    private static func decodeDataURL(_ dataURL: String) -> CGImage? {
        guard let comma = dataURL.firstIndex(of: ","),
              let data = Data(
                base64Encoded: String(dataURL[dataURL.index(after: comma)...]),
                options: .ignoreUnknownCharacters
              ),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func drawFrame(_ element: Element, in ctx: CGContext) {
        let rect = CGRect(x: element.x, y: element.y, width: element.width, height: element.height)
            .standardized
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(CGColor(gray: 0.73, alpha: 1))
        ctx.setLineWidth(2)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.strokePath()

        if let name = element.name, !name.isEmpty {
            let font = Fonts.font(family: 2, size: 14)
            let attributed = NSAttributedString(string: name, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0.6, alpha: 1),
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            ctx.textPosition = CGPoint(x: rect.minX, y: rect.minY - 6)
            CTLineDraw(line, ctx)
        }
        ctx.restoreGState()
    }

    private static func drawPlaceholder(_ element: Element, in ctx: CGContext) {
        let rect = CGRect(x: element.x, y: element.y, width: element.width, height: element.height)
            .standardized
        guard rect.width > 1, rect.height > 1 else { return }
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0.93, alpha: 1))
        ctx.setStrokeColor(CGColor(gray: 0.7, alpha: 1))
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        let path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Paint

    private static func roughOptions(_ element: Element) -> RoughOptions {
        RoughOptions(
            roughness: element.roughness,
            multiStroke: element.strokeStyle == "solid"
        )
    }

    private static func fill(_ path: CGPath, element: Element, in ctx: CGContext) {
        guard let color = Colors.parse(element.backgroundColor) else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        switch element.fillStyle {
        case "hachure", "cross-hatch", "zigzag":
            ctx.addPath(path)
            ctx.clip()
            ctx.setStrokeColor(color)
            ctx.setLineWidth(max(element.strokeWidth / 2, 0.5))
            ctx.setLineDash(phase: 0, lengths: [])
            let gap = max(element.strokeWidth * 4, 4)
            hatch(path.boundingBoxOfPath, angle: -41 * .pi / 180, gap: gap, in: ctx)
            if element.fillStyle == "cross-hatch" {
                hatch(path.boundingBoxOfPath, angle: 41 * .pi / 180, gap: gap, in: ctx)
            }
            ctx.strokePath()
        default:
            ctx.setFillColor(color)
            ctx.addPath(path)
            ctx.fillPath()
        }
    }

    private static func hatch(_ rect: CGRect, angle: Double, gap: CGFloat, in ctx: CGContext) {
        let span = hypot(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dir = CGPoint(x: cos(angle), y: sin(angle))
        let normal = CGPoint(x: -dir.y, y: dir.x)
        var offset = -span / 2
        while offset <= span / 2 {
            let origin = CGPoint(x: center.x + normal.x * offset, y: center.y + normal.y * offset)
            ctx.move(to: CGPoint(x: origin.x - dir.x * span / 2, y: origin.y - dir.y * span / 2))
            ctx.addLine(to: CGPoint(x: origin.x + dir.x * span / 2, y: origin.y + dir.y * span / 2))
            offset += gap
        }
    }

    private static func stroke(_ path: CGPath, element: Element, in ctx: CGContext) {
        guard let color = Colors.parse(element.strokeColor) else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(color)
        let width = element.strokeStyle == "solid" ? element.strokeWidth : element.strokeWidth + 0.5
        ctx.setLineWidth(width)
        switch element.strokeStyle {
        case "dashed": ctx.setLineDash(phase: 0, lengths: [8, 8 + element.strokeWidth])
        case "dotted": ctx.setLineDash(phase: 0, lengths: [1.5, 6 + element.strokeWidth])
        default: ctx.setLineDash(phase: 0, lengths: [])
        }
        ctx.addPath(path)
        ctx.strokePath()
    }
}
