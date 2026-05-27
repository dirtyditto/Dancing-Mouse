import CoreGraphics
import Foundation

// MARK: - IdleMonitor
//
// Fires `onIdle(_:)` when the cursor has been stationary for `idleDelay`
// seconds. Powers the optional "auto-dance when I walk away from my desk"
// feature in the menu UI.
//
// Why polling instead of another event tap? Stacking a second
// `.cghidEventTap` next to `InputMonitor`'s would mean every HID event
// crosses two callbacks, and the two taps could fight over enable/disable
// state. A 4 Hz timer is effectively free, doesn't require any extra
// permission grant, and decouples idle detection from the cancel path.

/// Monitors mouse inactivity and fires a callback after a configurable idle duration.
/// Uses a lightweight polling approach — checks if the cursor has moved since
/// the last sample rather than an event tap. This avoids interfering with InputMonitor.
final class IdleMonitor {
    private var timer: Timer?
    private var lastPosition: CGPoint = .zero
    private var stillSince: Date?
    private var isRunning = false

    /// Idle threshold in seconds before triggering.
    var idleDelay: TimeInterval = 10.0

    /// Called on the main thread when the cursor has been idle for `idleDelay` seconds.
    /// Receives the current (idle) cursor position.
    var onIdle: ((CGPoint) -> Void)?

    /// Whether the idle trigger has already fired for the current idle period.
    /// Reset when the cursor moves again.
    private var hasFired = false

    init() {}

    deinit { stop() }

    /// Start polling cursor position (4 Hz — very light).
    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastPosition = MouseMover.currentPosition
        stillSince = nil
        hasFired = false

        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// Stop monitoring.
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        stillSince = nil
        hasFired = false
    }

    private func poll() {
        let current = MouseMover.currentPosition
        let dx = abs(current.x - lastPosition.x)
        let dy = abs(current.y - lastPosition.y)
        let moved = dx > 1.5 || dy > 1.5 // Small threshold to ignore sub-pixel jitter.

        if moved {
            lastPosition = current
            stillSince = nil
            hasFired = false
            return
        }

        // Cursor is still.
        if stillSince == nil {
            stillSince = Date()
        }

        guard let since = stillSince, !hasFired else { return }

        if Date().timeIntervalSince(since) >= idleDelay {
            hasFired = true
            onIdle?(current)
        }
    }

    /// Reset the idle timer (e.g. after a dance completes, to avoid re-triggering immediately).
    func resetIdleTimer() {
        stillSince = nil
        hasFired = false
    }
}
