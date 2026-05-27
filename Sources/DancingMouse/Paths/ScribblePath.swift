import CoreGraphics
import Foundation
import AppKit

// MARK: - ScribblePath
//
// Pick N random control points inside a screen region, run a Catmull-Rom
// spline through them, and densify into a polyline. The result is a
// smooth, organic-looking curve with no hard corners.
//
// Why Catmull-Rom? Unlike Bezier, the spline passes *through* each control
// point — which means the random points we drew are actually visited,
// giving the scribble a recognizable wander. The tangent at each control
// point is set automatically from its neighbors, so the curve is C¹
// continuous.
//
// Coordinate convention: screen space (top-left origin), same as
// `CGEvent`. The first control point is anchored to `startPosition` when
// supplied so idle-triggered dances begin at the cursor (no teleport).

/// Generates a smooth, organic scribble using Catmull-Rom spline interpolation.
struct ScribblePath: CursorPath {
    let duration: TimeInterval
    private let splinePoints: [CGPoint]

    /// Create a random scribble within the given screen region.
    /// - Parameters:
    ///   - duration: Total animation time.
    ///   - pointCount: Number of random control points.
    ///   - region: Bounding region for the scribble.
    ///   - startPosition: When provided, the first control point is placed here
    ///     so the animation begins at the cursor's current position.
    init(duration: TimeInterval = 4.0, pointCount: Int = 12, region: CGRect? = nil, startPosition: CGPoint? = nil) {
        self.duration = duration

        let bounds = region ?? Self.defaultRegion()
        var controlPoints: [CGPoint] = []
        let margin: CGFloat = 50.0

        // If a start position is given, use it as the first control point.
        if let start = startPosition {
            controlPoints.append(start)
        }

        let remaining = pointCount - controlPoints.count
        for _ in 0..<remaining {
            let x = CGFloat.random(in: (bounds.minX + margin)...(bounds.maxX - margin))
            let y = CGFloat.random(in: (bounds.minY + margin)...(bounds.maxY - margin))
            controlPoints.append(CGPoint(x: x, y: y))
        }
        // Close loop for seamless repeat.
        if let first = controlPoints.first {
            controlPoints.append(first)
        }

        // Densify via Catmull-Rom interpolation.
        self.splinePoints = Self.catmullRomSpline(controlPoints: controlPoints, segmentsPerCurve: 30)
    }

    func point(at t: Double) -> CGPoint {
        guard splinePoints.count >= 2 else { return .zero }

        let clamped = max(0, min(1, t))
        let index = clamped * Double(splinePoints.count - 1)
        let lower = Int(index)
        let upper = min(lower + 1, splinePoints.count - 1)
        let frac = index - Double(lower)

        return CGPoint(
            x: Double(splinePoints[lower].x) + (Double(splinePoints[upper].x) - Double(splinePoints[lower].x)) * frac,
            y: Double(splinePoints[lower].y) + (Double(splinePoints[upper].y) - Double(splinePoints[lower].y)) * frac
        )
    }

    // MARK: - Catmull-Rom Spline

    /// Evaluates a Catmull-Rom spline through the given control points.
    ///
    /// For each pair of adjacent control points (p1, p2) the curve is shaped
    /// by their neighbors (p0, p3). The spline passes exactly through p1
    /// and p2 with tangents derived from (p2 - p0) and (p3 - p1). End
    /// points are duplicated via `max(i-1, 0)` / `min(i+1, count-1)` to
    /// gracefully handle the endpoints.
    ///
    /// The closed form used below is the standard 0.5-tension Catmull-Rom
    /// expansion:
    ///   C(t) = 0.5 · [ 2·p1
    ///                + (p2 - p0)·t
    ///                + (2·p0 - 5·p1 + 4·p2 - p3)·t²
    ///                + (-p0 + 3·p1 - 3·p2 + p3)·t³ ]
    private static func catmullRomSpline(controlPoints pts: [CGPoint], segmentsPerCurve: Int) -> [CGPoint] {
        guard pts.count >= 4 else { return pts }

        var result: [CGPoint] = []

        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[min(i + 1, pts.count - 1)]
            let p3 = pts[min(i + 2, pts.count - 1)]

            for s in 0..<segmentsPerCurve {
                let t = Double(s) / Double(segmentsPerCurve)
                let tt = t * t
                let ttt = tt * t

                // Catmull-Rom basis expansion (see doc above).
                let x = 0.5 * (
                    (2.0 * Double(p1.x)) +
                    (-Double(p0.x) + Double(p2.x)) * t +
                    (2.0 * Double(p0.x) - 5.0 * Double(p1.x) + 4.0 * Double(p2.x) - Double(p3.x)) * tt +
                    (-Double(p0.x) + 3.0 * Double(p1.x) - 3.0 * Double(p2.x) + Double(p3.x)) * ttt
                )
                let y = 0.5 * (
                    (2.0 * Double(p1.y)) +
                    (-Double(p0.y) + Double(p2.y)) * t +
                    (2.0 * Double(p0.y) - 5.0 * Double(p1.y) + 4.0 * Double(p2.y) - Double(p3.y)) * tt +
                    (-Double(p0.y) + 3.0 * Double(p1.y) - 3.0 * Double(p2.y) + Double(p3.y)) * ttt
                )
                result.append(CGPoint(x: x, y: y))
            }
        }

        if let last = pts.dropLast().last {
            result.append(last)
        }

        return result
    }

    private static func defaultRegion() -> CGRect {
        guard let screen = NSScreen.main else {
            return CGRect(x: 100, y: 100, width: 1200, height: 800)
        }
        // Inset from screen edges. CGEvent coordinates = top-left origin.
        return CGRect(x: 100, y: 100, width: screen.frame.width - 200, height: screen.frame.height - 200)
    }
}
