import CoreGraphics
import Foundation

// MARK: - GeometricPath
//
// Closed-form parametric shapes. Every point is computed from `t` ∈ [0, 1]
// using elementary trig — no precomputation, no allocation per sample, so
// these are extremely cheap to sweep at display-link rates.
//
// Shapes implemented:
//   - Circle      : (cos θ, sin θ)
//   - Figure 8    : Lissajous (sin θ, ½·sin 2θ)
//   - Spiral      : r grows linearly with t, swept 3× around
//   - Star        : 5-pointed; t is split into 5 segments, each segment
//                   linearly interpolates outer-vertex → inner-vertex →
//                   next outer-vertex
//
// Coordinate convention: CGEvent / CGWindow screen space, top-left origin
// with Y descending. Because `sin` is monotonic on [0, π], a positive
// `radius` rotates clockwise on screen (matches the user's intuition).
//
// Why `adjustedCenter`? When the dance is triggered manually we have the
// freedom to center on the screen, but when the *idle trigger* fires we
// want the path to begin at the cursor's current position so the user
// doesn't see a teleport — the cursor should glide out of where it
// already is. `adjustedCenter` solves for a center such that
// `point(at: 0) == startPosition`, per-shape.

/// Parametric geometric shapes: circle, figure-8, spiral, star.
enum GeometricShape: String, CaseIterable, Identifiable {
    case circle = "Circle"
    case figureEight = "Figure 8"
    case spiral = "Spiral"
    case star = "Star"

    var id: String { rawValue }
}

struct GeometricPath: CursorPath {
    let shape: GeometricShape
    let center: CGPoint
    let radius: CGFloat
    let duration: TimeInterval

    /// - Parameters:
    ///   - shape: The geometric shape to trace.
    ///   - center: Explicit center for the path. When nil, defaults to screen center.
    ///   - startPosition: When provided, the center is adjusted so that `point(at: 0)`
    ///     equals this position. Used by idle-triggered dances so the cursor doesn't jump.
    ///   - radius: Size of the shape in points.
    ///   - duration: Base animation duration in seconds.
    init(
        shape: GeometricShape,
        center: CGPoint? = nil,
        startPosition: CGPoint? = nil,
        radius: CGFloat = 200,
        duration: TimeInterval = 3.0
    ) {
        self.shape = shape
        self.radius = radius
        self.duration = duration

        if let startPosition {
            // Compute center so that point(at: 0) == startPosition.
            self.center = Self.adjustedCenter(
                for: shape, startPosition: startPosition, radius: radius,
                fallback: center ?? Self.screenCenter
            )
        } else {
            self.center = center ?? Self.screenCenter
        }
    }

    /// Compute the center offset so the shape begins at `startPosition`.
    private static func adjustedCenter(
        for shape: GeometricShape, startPosition: CGPoint, radius: CGFloat,
        fallback: CGPoint
    ) -> CGPoint {
        switch shape {
        case .circle:
            // At t=0: point = (center.x + radius, center.y)
            return CGPoint(x: startPosition.x - radius, y: startPosition.y)
        case .figureEight:
            // At t=0: point = (center.x + radius*sin(0), center.y + ...) = center
            return startPosition
        case .spiral:
            // At t=0: r0 = 0.2*radius, point = (center.x + r0, center.y)
            return CGPoint(x: startPosition.x - radius * 0.2, y: startPosition.y)
        case .star:
            // At t=0: first outer vertex at angle -π/2 → (center.x, center.y - radius)
            return CGPoint(x: startPosition.x, y: startPosition.y + radius)
        }
    }

    func point(at t: Double) -> CGPoint {
        switch shape {
        case .circle:
            return circlePoint(t)
        case .figureEight:
            return figureEightPoint(t)
        case .spiral:
            return spiralPoint(t)
        case .star:
            return starPoint(t)
        }
    }

    // MARK: - Shapes

    private func circlePoint(_ t: Double) -> CGPoint {
        let angle = 2.0 * Double.pi * t
        return CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }

    private func figureEightPoint(_ t: Double) -> CGPoint {
        let angle = 2.0 * Double.pi * t
        // Lissajous curve: x = sin(t), y = sin(2t)
        return CGPoint(
            x: center.x + radius * sin(angle),
            y: center.y + radius * 0.5 * sin(2.0 * angle)
        )
    }

    private func spiralPoint(_ t: Double) -> CGPoint {
        let angle = 2.0 * Double.pi * t * 3.0 // 3 rotations
        let r = radius * 0.2 + radius * 0.8 * t  // expanding radius
        return CGPoint(
            x: center.x + r * cos(angle),
            y: center.y + r * sin(angle)
        )
    }

    private func starPoint(_ t: Double) -> CGPoint {
        // 5-pointed star traced continuously.
        let points = 5
        let totalSegments = Double(points)
        let segment = t * totalSegments
        let segmentIndex = Int(segment) % points
        let segmentT = segment - Double(Int(segment))

        // Star vertices alternate between outer (tip) and inner (valley).
        let outerAngle = Double(segmentIndex * 2) * Double.pi * 2.0 / Double(points * 2) - Double.pi / 2.0
        let innerAngle = Double(segmentIndex * 2 + 1) * Double.pi * 2.0 / Double(points * 2) - Double.pi / 2.0
        let nextOuterAngle = Double(((segmentIndex + 1) % points) * 2) * Double.pi * 2.0 / Double(points * 2) - Double.pi / 2.0

        let innerRadius = radius * 0.4

        let outerPt = CGPoint(x: center.x + radius * cos(outerAngle), y: center.y + radius * sin(outerAngle))
        let innerPt = CGPoint(x: center.x + innerRadius * cos(innerAngle), y: center.y + innerRadius * sin(innerAngle))
        let nextOuterPt = CGPoint(x: center.x + radius * cos(nextOuterAngle), y: center.y + radius * sin(nextOuterAngle))

        // First half of segment: outer → inner. Second half: inner → next outer.
        if segmentT < 0.5 {
            let localT = segmentT * 2.0
            return lerp(from: outerPt, to: innerPt, t: localT)
        } else {
            let localT = (segmentT - 0.5) * 2.0
            return lerp(from: innerPt, to: nextOuterPt, t: localT)
        }
    }

    // MARK: - Helpers

    private func lerp(from a: CGPoint, to b: CGPoint, t: Double) -> CGPoint {
        CGPoint(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t
        )
    }

    private static var screenCenter: CGPoint {
        guard let screen = NSScreen.main else { return CGPoint(x: 500, y: 400) }
        // CGEvent uses top-left origin.
        return CGPoint(x: screen.frame.width / 2, y: screen.frame.height / 2)
    }
}

// NSScreen is in AppKit
import AppKit
