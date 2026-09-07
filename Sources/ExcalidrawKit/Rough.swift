import CoreGraphics
import Foundation

// A port of the parts of roughjs that Excalidraw actually uses to draw shapes,
// so a drawing saved with roughness 1 or 2 previews with the same wobble it has
// in the editor. Seeded from element.seed, so a given element always renders
// identically.
struct RoughRandom {
    private var seed: Int32

    init(seed: Int) {
        self.seed = Int32(truncatingIfNeeded: seed)
    }

    // Mirrors roughjs: ((2**31 - 1) & (seed = Math.imul(48271, seed))) / 2**31
    mutating func next() -> Double {
        if seed == 0 { return 0.5 }
        seed = seed.multipliedReportingOverflow(by: 48271).partialValue
        let masked = Int64(seed) & Int64(Int32.max)
        return Double(masked) / 2147483648.0
    }
}

struct RoughOptions {
    var roughness: Double
    var maxRandomnessOffset: Double = 2
    var bowing: Double = 1
    var multiStroke: Bool = true
    var preserveVertices: Bool = false
}

struct Rough {
    var random: RoughRandom
    var options: RoughOptions

    init(seed: Int, options: RoughOptions) {
        self.random = RoughRandom(seed: seed)
        self.options = options
    }

    private mutating func offset(_ min: Double, _ max: Double, gain: Double) -> Double {
        options.roughness * gain * (random.next() * (max - min) + min)
    }

    private mutating func offsetOpt(_ x: Double, gain: Double) -> Double {
        offset(-x, x, gain: gain)
    }

    /// One roughjs pass over a straight segment, emitted as a cubic bezier.
    mutating func line(
        into path: CGMutablePath,
        from a: CGPoint,
        to b: CGPoint,
        move: Bool,
        overlay: Bool
    ) {
        let lengthSq = pow(a.x - b.x, 2) + pow(a.y - b.y, 2)
        let length = sqrt(lengthSq)

        let gain: Double
        if length < 200 {
            gain = 1
        } else if length > 500 {
            gain = 0.4
        } else {
            gain = -0.0016668 * length + 1.233334
        }

        var off = options.maxRandomnessOffset
        if off * off * 100 > lengthSq { off = length / 10 }
        let halfOffset = off / 2
        let divergePoint = 0.2 + random.next() * 0.2

        var midDispX = options.bowing * options.maxRandomnessOffset * (b.y - a.y) / 200
        var midDispY = options.bowing * options.maxRandomnessOffset * (a.x - b.x) / 200
        midDispX = offsetOpt(midDispX, gain: gain)
        midDispY = offsetOpt(midDispY, gain: gain)

        let wobble = overlay ? halfOffset : off

        if move {
            let jx = options.preserveVertices ? 0 : offsetOpt(overlay ? halfOffset : off, gain: gain)
            let jy = options.preserveVertices ? 0 : offsetOpt(overlay ? halfOffset : off, gain: gain)
            path.move(to: CGPoint(x: a.x + jx, y: a.y + jy))
        }

        let c1 = CGPoint(
            x: midDispX + a.x + (b.x - a.x) * divergePoint + offsetOpt(wobble, gain: gain),
            y: midDispY + a.y + (b.y - a.y) * divergePoint + offsetOpt(wobble, gain: gain)
        )
        let c2 = CGPoint(
            x: midDispX + a.x + 2 * (b.x - a.x) * divergePoint + offsetOpt(wobble, gain: gain),
            y: midDispY + a.y + 2 * (b.y - a.y) * divergePoint + offsetOpt(wobble, gain: gain)
        )
        let end = CGPoint(
            x: b.x + (options.preserveVertices ? 0 : offsetOpt(wobble, gain: gain)),
            y: b.y + (options.preserveVertices ? 0 : offsetOpt(wobble, gain: gain))
        )
        path.addCurve(to: end, control1: c1, control2: c2)
    }

    /// roughjs draws every stroke twice; dashed and dotted strokes get one pass
    /// so the dash phases of the two passes cannot fight each other.
    mutating func polyline(_ points: [CGPoint], closed: Bool) -> CGPath {
        guard points.count >= 2 else { return CGMutablePath() }
        let path = CGMutablePath()
        var segments = zip(points, points.dropFirst()).map { ($0, $1) }
        if closed, let first = points.first, let last = points.last, first != last {
            segments.append((last, first))
        }

        for pass in 0..<(options.multiStroke ? 2 : 1) {
            for (index, segment) in segments.enumerated() {
                line(
                    into: path,
                    from: segment.0,
                    to: segment.1,
                    move: index == 0,
                    overlay: pass == 1
                )
            }
        }
        return path
    }

    /// Jitters each point, then fits a smooth curve through them — how roughjs
    /// approximates ellipses and curved multi-point lines.
    mutating func curve(_ points: [CGPoint], closed: Bool, jitter: Double) -> CGPath {
        guard points.count >= 2 else { return CGMutablePath() }
        let path = CGMutablePath()

        for pass in 0..<(options.multiStroke ? 2 : 1) {
            let amount = pass == 1 ? jitter / 2 : jitter
            let jittered = points.map { point in
                CGPoint(
                    x: point.x + offsetOpt(amount, gain: 1),
                    y: point.y + offsetOpt(amount, gain: 1)
                )
            }
            Curves.append(jittered, closed: closed, to: path)
        }
        return path
    }
}

enum Curves {
    /// Catmull-Rom through the given points, expressed as cubic beziers.
    static func append(_ points: [CGPoint], closed: Bool, to path: CGMutablePath) {
        guard points.count >= 2 else { return }
        guard points.count > 2 else {
            path.move(to: points[0])
            path.addLine(to: points[1])
            return
        }

        let count = points.count
        func point(_ index: Int) -> CGPoint {
            if closed {
                return points[((index % count) + count) % count]
            }
            return points[Swift.max(0, Swift.min(count - 1, index))]
        }

        path.move(to: point(0))
        let last = closed ? count : count - 1
        for i in 0..<last {
            let p0 = point(i - 1)
            let p1 = point(i)
            let p2 = point(i + 1)
            let p3 = point(i + 2)
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        if closed { path.closeSubpath() }
    }
}
