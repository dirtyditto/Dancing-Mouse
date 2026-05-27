import CoreGraphics
import CoreText
import Foundation
import AppKit

// MARK: - HandwritingPath
//
// Traces real glyph outlines so the cursor "writes" a string the way a pen
// would. Built once at init time; `point(at:)` then just walks the flat
// point list with linear interpolation.
//
// Pipeline:
//   1. For each character in the string, ask CoreText for its `CGPath`
//      (`CTFontCreatePathForGlyph`).
//   2. Flatten that path into a dense list of points
//      (`flattenPath` + Bezier subdivision for curves).
//   3. Between glyphs, splice in a smooth quadratic-Bezier "pen lift" arc
//      so the cursor doesn't jump straight across whitespace.
//   4. Concatenate everything into one polyline `segments` array.
//
// Coordinate-system gotcha: glyph paths use the typographic convention —
// origin at the baseline, Y *ascends* upward. The screen uses top-left
// origin with Y *descending*. `toScreen(_:)` flips Y once during
// translation; downstream samples are all in screen space.

/// Moves the cursor as if handwriting text, using glyph outlines from the system font.
struct HandwritingPath: CursorPath {
    let duration: TimeInterval
    private let segments: [CGPoint]
    /// Arc length from segments[0] to segments[i]. Used to walk the polyline at
    /// constant pixel-speed so the cursor doesn't crawl through curves and
    /// rocket across straight stretches.
    private let cumulativeDistance: [CGFloat]
    private let totalDistance: CGFloat

    /// Create a handwriting path for the given text string.
    /// - Parameters:
    ///   - text: The string to "write".
    ///   - fontSize: The rendered height of the text in screen points.
    ///   - origin: Top-left starting position in screen coordinates. Defaults to center-left of screen.
    ///   - startPosition: When provided, segments are shifted so `point(at: 0)` equals this
    ///     position. Required to avoid AnimationDriver's drift-detection cancelling on the first tick.
    ///   - duration: Total animation time in seconds.
    init(
        text: String,
        fontSize: CGFloat = 150,
        origin: CGPoint? = nil,
        startPosition: CGPoint? = nil,
        duration: TimeInterval = 5.0
    ) {
        self.duration = max(1.0, duration)
        let startOrigin = origin ?? Self.defaultOrigin(fontSize: fontSize)
        var built = Self.buildSegments(text: text, fontSize: fontSize, origin: startOrigin)

        if let startPosition, let first = built.first {
            let dx = startPosition.x - first.x
            let dy = startPosition.y - first.y
            if dx != 0 || dy != 0 {
                built = built.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            }
        }

        self.segments = built

        var cumulative: [CGFloat] = []
        cumulative.reserveCapacity(built.count)
        var running: CGFloat = 0
        cumulative.append(0)
        for i in 1..<built.count {
            let dx = built[i].x - built[i - 1].x
            let dy = built[i].y - built[i - 1].y
            running += hypot(dx, dy)
            cumulative.append(running)
        }
        self.cumulativeDistance = cumulative
        self.totalDistance = running
    }

    func point(at t: Double) -> CGPoint {
        guard segments.count >= 2 else { return segments.first ?? .zero }
        guard totalDistance > 0 else { return segments[0] }

        let clamped = max(0, min(1, t))
        let target = CGFloat(clamped) * totalDistance

        // Binary search for the largest index i with cumulativeDistance[i] <= target.
        var lo = 0
        var hi = cumulativeDistance.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if cumulativeDistance[mid] <= target {
                lo = mid
            } else {
                hi = mid - 1
            }
        }

        let lower = lo
        let upper = min(lower + 1, segments.count - 1)
        if lower == upper { return segments[lower] }

        let segLen = cumulativeDistance[upper] - cumulativeDistance[lower]
        let frac: CGFloat = segLen > 0 ? (target - cumulativeDistance[lower]) / segLen : 0

        return CGPoint(
            x: segments[lower].x + (segments[upper].x - segments[lower].x) * frac,
            y: segments[lower].y + (segments[upper].y - segments[lower].y) * frac
        )
    }

    // MARK: - Glyph Path Extraction

    private static func buildSegments(text: String, fontSize: CGFloat, origin: CGPoint) -> [CGPoint] {
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        var allPoints: [CGPoint] = []
        var xOffset: CGFloat = 0

        for char in text {
            guard let scalar = char.unicodeScalars.first else { continue }
            var glyph = CTFontGetGlyphWithName(font, String(char) as CFString)

            // If glyph not found by name, try character mapping.
            if glyph == 0 {
                var chars = [UniChar](String(scalar).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: chars.count)
                CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count)
                glyph = glyphs[0]
            }

            if glyph == 0 {
                // Unprintable — advance by a space width.
                xOffset += fontSize * 0.4
                continue
            }

            // Get glyph path.
            guard let glyphPath = CTFontCreatePathForGlyph(font, glyph, nil) else {
                xOffset += fontSize * 0.4
                continue
            }

            // Extract path elements and flatten to line segments.
            let glyphSegments = flattenPath(glyphPath)

            // If there are segments, add a pen-lift arc from previous position.
            if !allPoints.isEmpty, let firstGlyphPt = glyphSegments.first {
                let target = CGPoint(x: firstGlyphPt.x + xOffset, y: firstGlyphPt.y)
                let screenTarget = toScreen(target, origin: origin, fontSize: fontSize)
                let lastPt = allPoints.last!
                // Smooth arc for pen-lift transition.
                let arcPoints = penLiftArc(from: lastPt, to: screenTarget, steps: 15)
                allPoints.append(contentsOf: arcPoints)
            }

            // Add glyph segments translated to position.
            for pt in glyphSegments {
                let translated = CGPoint(x: pt.x + xOffset, y: pt.y)
                allPoints.append(toScreen(translated, origin: origin, fontSize: fontSize))
            }

            // Advance by glyph width.
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            xOffset += advance.width
        }

        return allPoints
    }

    /// Flattens a CGPath into an array of points (line approximation of curves).
    /// Walks the original path directly — `copy(strokingWithWidth:)` would
    /// produce a doubled (outer + reversed inner) trace which makes the cursor
    /// retrace every letter twice.
    private static func flattenPath(_ path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = []
        var subpathStart: CGPoint = .zero

        path.applyWithBlock { elementPtr in
            let element = elementPtr.pointee
            switch element.type {
            case .moveToPoint:
                let p = element.points[0]
                points.append(p)
                subpathStart = p
            case .addLineToPoint:
                points.append(element.points[0])
            case .addQuadCurveToPoint:
                if let last = points.last {
                    let subdivided = subdivideQuad(
                        p0: last,
                        p1: element.points[0],
                        p2: element.points[1],
                        steps: 8
                    )
                    points.append(contentsOf: subdivided)
                }
            case .addCurveToPoint:
                if let last = points.last {
                    let subdivided = subdivideCubic(
                        p0: last,
                        p1: element.points[0],
                        p2: element.points[1],
                        p3: element.points[2],
                        steps: 12
                    )
                    points.append(contentsOf: subdivided)
                }
            case .closeSubpath:
                // Close back to the start of the current subpath, not the
                // global first point.
                points.append(subpathStart)
            @unknown default:
                break
            }
        }

        return points
    }

    /// Sample a quadratic Bezier at `steps` equally-spaced values of t.
    /// B(t) = (1-t)²·p0 + 2(1-t)t·p1 + t²·p2
    private static func subdivideQuad(p0: CGPoint, p1: CGPoint, p2: CGPoint, steps: Int) -> [CGPoint] {
        var result: [CGPoint] = []
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let mt = 1.0 - t
            let x = mt * mt * Double(p0.x) + 2 * mt * t * Double(p1.x) + t * t * Double(p2.x)
            let y = mt * mt * Double(p0.y) + 2 * mt * t * Double(p1.y) + t * t * Double(p2.y)
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }

    /// Sample a cubic Bezier at `steps` equally-spaced values of t.
    /// B(t) = (1-t)³·p0 + 3(1-t)²t·p1 + 3(1-t)t²·p2 + t³·p3
    private static func subdivideCubic(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, steps: Int) -> [CGPoint] {
        var result: [CGPoint] = []
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let mt = 1.0 - t
            let mt2 = mt * mt
            let mt3 = mt2 * mt
            let t2 = t * t
            let t3 = t2 * t
            let x = mt3 * Double(p0.x) + 3 * mt2 * t * Double(p1.x) + 3 * mt * t2 * Double(p2.x) + t3 * Double(p3.x)
            let y = mt3 * Double(p0.y) + 3 * mt2 * t * Double(p1.y) + 3 * mt * t2 * Double(p2.y) + t3 * Double(p3.y)
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }

    /// Converts glyph coordinates (origin bottom-left, ascending Y) to screen coordinates (top-left origin).
    private static func toScreen(_ point: CGPoint, origin: CGPoint, fontSize: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + point.x,
            y: origin.y + (fontSize - point.y) // Flip Y: glyph Y ascends, screen Y descends.
        )
    }

    /// Creates a smooth ballistic arc between two points (pen-lift transition).
    private static func penLiftArc(from: CGPoint, to: CGPoint, steps: Int) -> [CGPoint] {
        var result: [CGPoint] = []
        let midX = (from.x + to.x) / 2
        let midY = min(from.y, to.y) - 30.0 // Arc upward (screen coords: smaller Y = higher).

        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let eased = Easing.easeInOutCubic(t)
            // Quadratic Bezier through the arc point.
            let mt = 1.0 - eased
            let x = mt * mt * Double(from.x) + 2 * mt * eased * Double(midX) + eased * eased * Double(to.x)
            let y = mt * mt * Double(from.y) + 2 * mt * eased * Double(midY) + eased * eased * Double(to.y)
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }

    private static func defaultOrigin(fontSize: CGFloat) -> CGPoint {
        guard let screen = NSScreen.main else { return CGPoint(x: 200, y: 300) }
        return CGPoint(
            x: screen.frame.width * 0.15,
            y: (screen.frame.height - fontSize) / 2
        )
    }
}
