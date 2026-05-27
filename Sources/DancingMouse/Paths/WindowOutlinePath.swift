import CoreGraphics
import Foundation
import Cocoa

// MARK: - WindowOutlinePath
//
// Finds the frontmost non-self window via `CGWindowListCopyWindowInfo`,
// then traces its rounded rectangle: four quarter-circle corner arcs
// strung together with straight edges (built implicitly by walking
// arc-to-arc).
//
// Coordinate-system note: `kCGWindowBounds` already reports top-left
// screen coordinates with Y descending, which matches what
// `CGWarpMouseCursorPosition` expects — no flipping required.
//
// Sampling: `point(at: t)` walks the polyline by *arc length* (not point
// index), so the cursor moves at a constant speed along the perimeter
// regardless of how the arcs were subdivided.

/// Traces the outline of the frontmost window as a rounded rectangle.
struct WindowOutlinePath: CursorPath {
    let duration: TimeInterval
    private let corners: [CGPoint]

    init(duration: TimeInterval = 3.0, cornerRadius: CGFloat = 12.0) {
        self.duration = duration
        self.corners = Self.buildWindowOutline(cornerRadius: cornerRadius)
    }

    func point(at t: Double) -> CGPoint {
        guard corners.count >= 2 else {
            // Fallback: if no window found, circle in center.
            let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            let cx = screen.width / 2
            let cy = screen.height / 2
            let angle = 2.0 * Double.pi * t
            return CGPoint(x: cx + 200 * cos(angle), y: cy + 200 * sin(angle))
        }

        // Walk along the polyline by normalized arc length.
        let totalLength = Self.polylineLength(corners)
        let targetDist = t * totalLength

        var accumulated = 0.0
        for i in 0..<(corners.count - 1) {
            let segLen = Self.distance(corners[i], corners[i + 1])
            if accumulated + segLen >= targetDist {
                let segT = (targetDist - accumulated) / max(segLen, 0.001)
                return Self.lerp(corners[i], corners[i + 1], segT)
            }
            accumulated += segLen
        }

        return corners.last!
    }

    // MARK: - Build outline from frontmost window

    private static func buildWindowOutline(cornerRadius cr: CGFloat) -> [CGPoint] {
        guard let rect = frontmostWindowRect() else { return [] }

        // Subdivide each corner arc into segments for smooth tracing.
        let arcSegments = 8
        var points: [CGPoint] = []

        // Top-left corner arc
        for i in 0...arcSegments {
            let angle = Double.pi + Double.pi / 2.0 * Double(i) / Double(arcSegments)
            points.append(CGPoint(
                x: rect.minX + cr + cr * cos(angle),
                y: rect.minY + cr + cr * sin(angle)
            ))
        }
        // Top-right corner arc
        for i in 0...arcSegments {
            let angle = 3.0 * Double.pi / 2.0 + Double.pi / 2.0 * Double(i) / Double(arcSegments)
            points.append(CGPoint(
                x: rect.maxX - cr + cr * cos(angle),
                y: rect.minY + cr + cr * sin(angle)
            ))
        }
        // Bottom-right corner arc
        for i in 0...arcSegments {
            let angle = 0.0 + Double.pi / 2.0 * Double(i) / Double(arcSegments)
            points.append(CGPoint(
                x: rect.maxX - cr + cr * cos(angle),
                y: rect.maxY - cr + cr * sin(angle)
            ))
        }
        // Bottom-left corner arc
        for i in 0...arcSegments {
            let angle = Double.pi / 2.0 + Double.pi / 2.0 * Double(i) / Double(arcSegments)
            points.append(CGPoint(
                x: rect.minX + cr + cr * cos(angle),
                y: rect.maxY - cr + cr * sin(angle)
            ))
        }
        // Close the loop.
        if let first = points.first {
            points.append(first)
        }

        return points
    }

    private static func frontmostWindowRect() -> CGRect? {
        // Get all on-screen windows, find the frontmost one that isn't the desktop or our own app.
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier

        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  pid != ownPID,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"],
                  w > 50, h > 50 // skip tiny windows (e.g., menu bar items)
            else { continue }

            // kCGWindowBounds uses top-left screen coordinates (same as CGEvent).
            return CGRect(x: x, y: y, width: w, height: h)
        }

        return nil
    }

    // MARK: - Geometry helpers

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x)
        let dy = Double(b.y - a.y)
        return sqrt(dx * dx + dy * dy)
    }

    private static func polylineLength(_ points: [CGPoint]) -> Double {
        var total = 0.0
        for i in 0..<(points.count - 1) {
            total += distance(points[i], points[i + 1])
        }
        return total
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(
            x: Double(a.x) + (Double(b.x) - Double(a.x)) * t,
            y: Double(a.y) + (Double(b.y) - Double(a.y)) * t
        )
    }
}
