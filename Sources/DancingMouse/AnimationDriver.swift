import Foundation
import CoreGraphics
import QuartzCore
import os

// MARK: - AnimationDriver
//
// The frame loop. Given a `CursorPath` and an easing function, this class
// samples `path.point(at: easedT)` once per display refresh and warps the
// cursor (via `MouseMover`) to that point.
//
// Threading:
//   - `tick()` runs on the CVDisplayLink callback thread (or, when that's
//     unavailable, a 120 Hz `Timer` on the main run loop as a fallback).
//   - The cursor warp itself is synchronous on that thread — fast and
//     non-blocking.
//   - UI callbacks (`onFrame`, `onComplete`, `onUserInterrupt`) are
//     dispatched to the main queue, with `onFrame` throttled to ~30 Hz so a
//     fast display link doesn't saturate the main queue.
//
// Cancellation:
//   - `requestCancel()` is safe to call from any thread. It flips an
//     `OSAllocatedUnfairLock`-protected flag that `tick()` checks first,
//     before doing any work. This is what lets `InputMonitor` cancel an
//     active dance from its own event-tap thread within a single frame —
//     no main-queue hop, so a busy main queue can't delay the cursor
//     stopping.
//   - In addition, `tick()` runs a drift check: if the actual cursor
//     position has diverged from `lastWarpedPosition` by more than a few
//     points, the user must have moved the mouse between frames and we
//     bail out the same way.

/// Drives cursor animation using a high-frequency display-linked timer.
/// Each frame samples the current `CursorPath` at a normalized time, applies easing,
/// and moves the cursor.
final class AnimationDriver {
    private var displayLink: CVDisplayLink?
    private var timer: Timer?
    private var startTime: CFTimeInterval = 0
    private var path: CursorPath?
    private var easingFn: (Double) -> Double = Easing.easeInOutCubic
    private var speedMultiplier: Double = 1.0
    private var shouldRepeat: Bool = false
    private var isRunning: Bool = false

    /// Thread-safe cancel flag. Can be set from ANY thread (e.g. the event tap
    /// thread) and is checked on the display-link thread every tick.
    /// This bypasses the main queue entirely so cancellation is never delayed
    /// by queued frame dispatches.
    private let cancelRequested = OSAllocatedUnfairLock(initialState: false)

    /// Called every frame with the new cursor position.
    var onFrame: ((CGPoint) -> Void)?

    /// Called when the animation reaches the end (and repeat is off).
    var onComplete: (() -> Void)?

    /// Called when the animation is cancelled (via `requestCancel()` or drift detection).
    /// Always fired on the main thread.
    var onUserInterrupt: (() -> Void)?

    /// Last position we warped the cursor to, used to detect user-initiated drift.
    private var lastWarpedPosition: CGPoint?

    /// Throttle: only dispatch onFrame at ~30 fps to avoid saturating the main queue.
    private var lastFrameDispatchTime: CFTimeInterval = 0
    private let frameDispatchInterval: CFTimeInterval = 1.0 / 30.0

    init() {}

    deinit {
        stop()
    }

    /// Request immediate cancellation from any thread.
    /// This is the primary way external code (InputMonitor) should stop the animation.
    /// It sets an atomic flag checked every tick — no main queue delay.
    func requestCancel() {
        cancelRequested.withLock { $0 = true }
    }

    /// Start animating along the given path.
    func start(
        path: CursorPath,
        easing: @escaping (Double) -> Double = Easing.easeInOutCubic,
        speedMultiplier: Double = 1.0,
        shouldRepeat: Bool = false
    ) {
        stop()

        cancelRequested.withLock { $0 = false }

        self.path = path
        self.easingFn = easing
        self.speedMultiplier = max(0.1, speedMultiplier)
        self.shouldRepeat = shouldRepeat
        self.startTime = CACurrentMediaTime()
        self.isRunning = true
        self.lastFrameDispatchTime = 0

        // Seed with the first point so the very first tick can detect
        // if the user moved the cursor since the animation started.
        self.lastWarpedPosition = path.point(at: 0)

        if !startDisplayLink() {
            startTimerFallback()
        }
    }

    /// Stop animation immediately. Must be called from the main thread for cleanup.
    func stop() {
        isRunning = false

        if let dl = displayLink {
            CVDisplayLinkStop(dl)
            displayLink = nil
        }

        timer?.invalidate()
        timer = nil

        lastWarpedPosition = nil
        path = nil
    }

    var running: Bool { isRunning }

    // MARK: - Display Link

    private func startDisplayLink() -> Bool {
        var dl: CVDisplayLink?
        let status = CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard status == kCVReturnSuccess, let dl else { return false }

        let unmanagedSelf = Unmanaged.passUnretained(self)
        CVDisplayLinkSetOutputCallback(dl, { (_, _, _, _, _, userInfo) -> CVReturn in
            guard let userInfo else { return kCVReturnError }
            let driver = Unmanaged<AnimationDriver>.fromOpaque(userInfo).takeUnretainedValue()
            driver.tick()
            return kCVReturnSuccess
        }, unmanagedSelf.toOpaque())

        CVDisplayLinkStart(dl)
        displayLink = dl
        return true
    }

    // MARK: - Timer Fallback (120 Hz)

    private func startTimerFallback() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    // MARK: - Frame Tick

    private func tick() {
        guard isRunning, let path else { return }

        // --- Check thread-safe cancel flag FIRST (set by InputMonitor). ---
        let shouldCancel = cancelRequested.withLock { $0 }
        if shouldCancel {
            isRunning = false
            DispatchQueue.main.async { [weak self] in
                self?.stop()
                self?.onUserInterrupt?()
            }
            return
        }

        // --- Drift detection: detect user mouse movement BEFORE warping. ---
        if let last = lastWarpedPosition {
            let actual = CGEvent(source: nil)?.location ?? last
            let dx = abs(actual.x - last.x)
            let dy = abs(actual.y - last.y)
            if dx > 2.0 || dy > 2.0 {
                isRunning = false
                DispatchQueue.main.async { [weak self] in
                    self?.stop()
                    self?.onUserInterrupt?()
                }
                return
            }
        }

        let elapsed = CACurrentMediaTime() - startTime
        let effectiveDuration = path.duration / speedMultiplier
        var t = elapsed / effectiveDuration

        if t >= 1.0 {
            if shouldRepeat {
                startTime = CACurrentMediaTime()
                t = 0.0
            } else {
                t = 1.0
                let easedT = easingFn(t)
                let point = path.point(at: easedT)
                MouseMover.moveTo(point)
                lastWarpedPosition = point
                isRunning = false
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.onFrame?(point)
                    self.stop()
                    self.onComplete?()
                }
                return
            }
        }

        let easedT = easingFn(max(0, min(1, t)))
        let point = path.point(at: easedT)

        MouseMover.moveTo(point)
        lastWarpedPosition = point

        // Throttle UI updates to ~30 fps to keep the main queue responsive.
        let now = CACurrentMediaTime()
        if now - lastFrameDispatchTime >= frameDispatchInterval {
            lastFrameDispatchTime = now
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning else { return }
                self.onFrame?(point)
            }
        }
    }
}
