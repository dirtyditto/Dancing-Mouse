import CoreGraphics
import Foundation

// MARK: - MouseMover
//
// The only place in the app that moves the system cursor. `AnimationDriver`
// calls `moveTo(_:)` on every tick.
//
// Two important details:
//   1. We use `CGWarpMouseCursorPosition` (not synthesized mouseMoved events)
//      because it's the most reliable way to teleport the pointer on macOS,
//      and it doesn't generate a mouse-moved event the user would have to
//      "out-race".
//   2. Even though warps don't generate normal mouse events, the event tap in
//      `InputMonitor` will see *some* HID activity. Every event this enum
//      produces is implicitly tagged via the event source userData field —
//      `syntheticTag` is the agreed-upon magic value the two sides share.

/// Moves the system cursor by warping its position.
///
/// The companion to `InputMonitor`: they coordinate via `syntheticTag` so the
/// event tap can distinguish self-generated moves from a real user grabbing
/// the mouse.
enum MouseMover {
    /// Magic value written to `eventSourceUserData` on every synthetic event.
    ///
    /// The literal hex spells "DA9CE" ≈ "DANCE" — chosen so it's recognizable
    /// in a packet capture or `CGEventGet` dump, and unlikely to collide with
    /// values used by other tools.
    static let syntheticTag: Int64 = 0xDA9CE

    /// Move the cursor to `point` in screen coordinates (top-left origin).
    ///
    /// `CGWarpMouseCursorPosition` directly repositions the system cursor
    /// without posting any mouse-moved event. This is faster and more
    /// reliable than `CGEvent`-based synthesis, and it avoids most of the
    /// noisy interactions with `InputMonitor`.
    @discardableResult
    static func moveTo(_ point: CGPoint) -> Bool {
        let err = CGWarpMouseCursorPosition(point)
        // After a warp, macOS briefly disassociates the physical mouse from
        // the on-screen cursor (a ~250ms "dead zone" intended to prevent the
        // cursor from snapping back). Re-associating immediately is what makes
        // the cancel-on-input contract feel instantaneous: as soon as the
        // user nudges the mouse, the cursor responds.
        CGAssociateMouseAndMouseCursorPosition(1)
        return err == .success
    }

    /// Returns the current cursor position in screen coordinates.
    /// Using a `nil`-source event is the canonical way to query the live
    /// pointer location on macOS.
    static var currentPosition: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}
