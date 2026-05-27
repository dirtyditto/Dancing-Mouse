import Cocoa
import QuartzCore

// MARK: - CursorTrailRenderer
//
// Draws the optional ghost trail behind the moving cursor.
//
// Architecture:
//   - A borderless, click-through `NSWindow` at `.screenSaver` level covers
//     the main display. Its content view hosts a `CALayer` that we
//     re-render whenever a new cursor position arrives.
//   - `AnimationDriver` → `DanceOrchestrator.handleAnimationComplete`'s
//     `onFrame` callback feeds positions in here at ~30 Hz (the driver
//     throttles to keep the main queue responsive).
//   - All the look-and-feel knobs come from the @Observable
//     `TrailConfiguration`, so SwiftUI sliders update the trail live.
//
// Coordinate-system note: `CGEvent` reports cursor positions in *top-left*
// screen coordinates, but a `CALayer` hosted in an `NSView` uses
// *bottom-left* by default. We flip Y once in `appendPosition(_:)` so the
// trail layer can keep its natural orientation.

/// Renders a fading ghost trail behind the cursor using a transparent overlay window.
final class CursorTrailRenderer {
    private var overlayWindow: NSWindow?
    private var trailLayer: TrailLayer?
    private var positions: [CGPoint] = []
    private var config: TrailConfiguration

    init(configuration: TrailConfiguration) {
        self.config = configuration
    }

    /// Show the overlay window and prepare for trail rendering.
    func show() {
        guard config.enabled else { return }
        guard let screen = NSScreen.main else { return }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let layer = TrailLayer()
        layer.frame = CGRect(origin: .zero, size: screen.frame.size)
        layer.contentsScale = screen.backingScaleFactor
        layer.needsDisplayOnBoundsChange = true

        let hostView = NSView(frame: screen.frame)
        hostView.wantsLayer = true
        hostView.layer = CALayer()
        hostView.layer?.addSublayer(layer)

        window.contentView = hostView
        window.orderFrontRegardless()

        self.overlayWindow = window
        self.trailLayer = layer
        self.positions = []
    }

    /// Hide the overlay and clear the trail.
    func hide() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        trailLayer = nil
        positions = []
    }

    /// Append a new cursor position and redraw the trail.
    func appendPosition(_ point: CGPoint) {
        guard config.enabled, trailLayer != nil else { return }

        positions.append(point)
        // Trim to configured length.
        if positions.count > config.length {
            positions.removeFirst(positions.count - config.length)
        }

        // `CGEvent` positions use top-left screen coordinates, but the
        // hosting `CALayer` defaults to bottom-left. Flip Y once here so the
        // layer's draw(in:) call can stay coordinate-system-agnostic.
        guard let screen = NSScreen.main else { return }
        let flippedPositions = positions.map { pt -> CGPoint in
            CGPoint(x: pt.x, y: screen.frame.height - pt.y)
        }

        trailLayer?.positions = flippedPositions
        trailLayer?.trailConfig = config
        trailLayer?.setNeedsDisplay()
    }

    /// Update the configuration (can be called while trail is visible).
    func updateConfiguration(_ newConfig: TrailConfiguration) {
        self.config = newConfig
    }
}

// MARK: - Trail CALayer

private class TrailLayer: CALayer {
    var positions: [CGPoint] = []
    var trailConfig: TrailConfiguration?

    override func draw(in ctx: CGContext) {
        guard let config = trailConfig, !positions.isEmpty else { return }

        let total = positions.count
        let baseColor = config.effectiveColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        baseColor.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)

        // Draw from oldest (index 0) to newest (index total-1).
        for i in 0..<total {
            let age = total - 1 - i  // 0 = newest, total-1 = oldest
            let fadeOpacity = config.fadeStyle.opacity(at: age, total: total)
            let alpha = config.opacity * fadeOpacity
            guard alpha > 0.01 else { continue }

            // Newer dots are larger, older dots shrink.
            let sizeFactor = CGFloat(fadeOpacity)
            let dotDiameter = config.dotSize * max(0.3, sizeFactor)

            let color = CGColor(srgbRed: r, green: g, blue: b, alpha: CGFloat(alpha))
            ctx.setFillColor(color)

            let rect = CGRect(
                x: positions[i].x - dotDiameter / 2,
                y: positions[i].y - dotDiameter / 2,
                width: dotDiameter,
                height: dotDiameter
            )
            ctx.fillEllipse(in: rect)
        }
    }
}
