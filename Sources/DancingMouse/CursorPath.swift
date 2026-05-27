import CoreGraphics
import Foundation

// MARK: - CursorPath
//
// The single abstraction every dance pattern conforms to. `AnimationDriver`
// samples a path at a normalized time `t` ∈ [0, 1] (after applying an easing
// curve) and warps the cursor to the resulting screen point.
//
// Conforming types live in `Sources/DancingMouse/Paths/`:
//   - GeometricPath    (circle / figure-8 / spiral / star)
//   - HandwritingPath  (CoreText glyph outlines)
//   - ScribblePath     (Catmull-Rom spline)
//   - WindowOutlinePath (rectangle of the frontmost window)
//
// All implementations return points in screen coordinates (top-left origin,
// same convention as CGEvent / CGWindow).

/// A path that the cursor can follow during a dance.
///
/// Implementations are immutable value types — built once, sampled many times
/// per second on the animation-driver thread. They must therefore be
/// thread-safe and side-effect-free: the only contract is "given `t`, give me
/// a screen point."
protocol CursorPath {
    /// The point on the path at normalized time `t` (0 = start, 1 = end).
    /// Implementations should clamp `t` defensively — callers usually do, but
    /// rounding error at the endpoints can push it slightly outside [0, 1].
    func point(at t: Double) -> CGPoint

    /// Total duration of this path in seconds, *before* the user's speed
    /// multiplier is applied by `AnimationDriver`.
    var duration: TimeInterval { get }
}
