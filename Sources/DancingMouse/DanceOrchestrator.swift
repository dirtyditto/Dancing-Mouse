import Foundation
import Observation

// MARK: - DanceOrchestrator
//
// The brain of the app. Owns the UI-visible state (selected pattern, speed,
// easing, trail config, idle-trigger settings) and wires together every
// subsystem:
//
//                          ┌─ AnimationDriver  (frame loop / cursor warp)
//                          ├─ CursorTrailRenderer (overlay window)
//   DanceOrchestrator ─────┼─ InputMonitor    (cancel-on-input enforcer)
//                          ├─ IdleMonitor     (auto-trigger when stationary)
//                          └─ MouseMover      (low-level cursor warp)
//
// The state machine is intentionally tiny — `.idle` ↔ `.dancing`. Every
// transition out of `.dancing` flows through `cancelImmediately()` to keep
// teardown in one place: stop the driver, hide the trail, stop input
// monitoring, optionally restore the cursor, and re-arm the idle monitor.
//
// The "idle loop" is a small extra wrinkle: if the dance was started by
// the idle trigger, after it completes we wait ~1s and re-run from the
// same position — but only if the cursor hasn't moved in the meantime,
// because any movement implies the user came back to the keyboard.

/// The available dance patterns.
enum DancePattern: String, CaseIterable, Identifiable {
    case circle = "Circle"
    case figureEight = "Figure 8"
    case spiral = "Spiral"
    case star = "Star"
    case windowOutline = "Window Outline"
    case scribble = "Scribble"
    case handwriting = "Handwriting"

    var id: String { rawValue }
}

/// State of the dance orchestrator.
enum DanceState: Equatable {
    case idle
    case dancing
}

/// Central coordinator for the Dancing Mouse app.
/// Manages the state machine, wires up animation, trail, and input monitoring.
@Observable
final class DanceOrchestrator {
    var state: DanceState = .idle
    var selectedPattern: DancePattern = .circle
    var handwritingText: String = "hello"
    var speedMultiplier: Double = 1.0
    var easingPreset: EasingPreset = .cubic
    var shouldRepeat: Bool = false
    var restoreCursor: Bool = false

    // Idle trigger settings
    var idleTriggerEnabled: Bool = false {
        didSet { updateIdleMonitor() }
    }
    var idleDelay: Double = 10.0 { // seconds
        didSet { idleMonitor.idleDelay = idleDelay }
    }
    var idlePattern: DancePattern = .circle

    let trailConfig = TrailConfiguration()

    private let animationDriver = AnimationDriver()
    private let inputMonitor = InputMonitor()
    private let idleMonitor = IdleMonitor()
    private var trailRenderer: CursorTrailRenderer?
    private var savedCursorPosition: CGPoint?

    /// Tracks whether the current dance was started by the idle trigger,
    /// so we can re-run with a short delay instead of the full idle timeout.
    private var idleLoopActive: Bool = false
    private var idleLoopPosition: CGPoint?
    private let idleLoopDelay: TimeInterval = 1.0 // seconds between idle re-runs

    init() {
        // Wire input monitor: any real user input → cancel immediately.
        inputMonitor.onUserInput = { [weak self] in
            self?.cancelImmediately()
        }
        // Wire the immediate (thread-safe) cancel so the animation driver
        // stops on the very next tick, even if the main queue is busy.
        inputMonitor.onImmediateCancel = { [weak self] in
            self?.animationDriver.requestCancel()
        }

        // Wire animation driver callbacks.
        animationDriver.onFrame = { [weak self] point in
            self?.trailRenderer?.appendPosition(point)
        }
        animationDriver.onComplete = { [weak self] in
            self?.handleAnimationComplete()
        }

        // Wire user-interrupt detection: if the animation driver detects the
        // cursor was moved by the user (position drift), cancel immediately.
        animationDriver.onUserInterrupt = { [weak self] in
            self?.cancelImmediately()
        }

        // Wire idle monitor: start a dance at the current cursor position after idle timeout.
        idleMonitor.idleDelay = idleDelay
        idleMonitor.onIdle = { [weak self] cursorPosition in
            guard let self, self.state == .idle, self.idleTriggerEnabled else { return }
            self.startDanceAtPosition(pattern: self.idlePattern, position: cursorPosition)
        }
    }

    // MARK: - Public API

    /// Start dancing with the currently selected pattern.
    func startDance() {
        guard state == .idle else { return }

        let currentPos = MouseMover.currentPosition
        let path = buildPath(for: selectedPattern, atPosition: currentPos)
        guard let path else { return }

        // Save cursor position for optional restore.
        if restoreCursor {
            savedCursorPosition = MouseMover.currentPosition
        }

        state = .dancing

        // Set up trail renderer.
        trailRenderer = CursorTrailRenderer(configuration: trailConfig)
        trailRenderer?.show()

        // Start input monitoring.
        inputMonitor.start()

        // Start animation.
        animationDriver.start(
            path: path,
            easing: easingPreset.function,
            speedMultiplier: speedMultiplier,
            shouldRepeat: shouldRepeat
        )
    }

    /// Start a specific pattern directly (used by hotkey manager).
    func startPattern(_ pattern: DancePattern) {
        if state == .dancing {
            cancelImmediately()
        }
        selectedPattern = pattern
        startDance()
    }

    /// Start a dance centered at a specific screen position (used by idle trigger).
    func startDanceAtPosition(pattern: DancePattern, position: CGPoint) {
        if state == .dancing {
            cancelImmediately()
        }

        let path = buildPath(for: pattern, atPosition: position)
        guard let path else { return }

        if restoreCursor {
            savedCursorPosition = position
        }

        state = .dancing
        idleMonitor.stop()
        idleLoopActive = true
        idleLoopPosition = position

        trailRenderer = CursorTrailRenderer(configuration: trailConfig)
        trailRenderer?.show()
        inputMonitor.start()

        animationDriver.start(
            path: path,
            easing: easingPreset.function,
            speedMultiplier: speedMultiplier,
            shouldRepeat: shouldRepeat
        )
    }

    /// Immediately cancel the current dance. This is the #1 rule enforcement.
    /// Called by InputMonitor on any real user input, or by the user pressing Stop.
    func cancelImmediately() {
        // Stop animation regardless of state — handles both active dancing
        // and the idle-loop gap (where state is .idle but a restart is pending).
        animationDriver.stop()
        trailRenderer?.hide()
        trailRenderer = nil
        inputMonitor.stop()

        // Break the idle loop — user interrupted.
        idleLoopActive = false
        idleLoopPosition = nil

        // Restore cursor position if configured and we were dancing.
        if state == .dancing {
            if restoreCursor, let saved = savedCursorPosition {
                MouseMover.moveTo(saved)
            }
        }
        savedCursorPosition = nil

        state = .idle

        // Restart idle monitor if enabled.
        updateIdleMonitor()
    }

    /// Toggle dance on/off.
    func toggle() {
        if state == .dancing {
            cancelImmediately()
        } else {
            startDance()
        }
    }

    // MARK: - Private

    private func handleAnimationComplete() {
        trailRenderer?.hide()
        trailRenderer = nil

        if restoreCursor, let saved = savedCursorPosition {
            MouseMover.moveTo(saved)
        }
        savedCursorPosition = nil

        state = .idle

        // If this was an idle-triggered dance, re-run after a short delay
        // instead of waiting for the full idle timeout again.
        // IMPORTANT: Keep inputMonitor running during the gap so user input
        // is detected and cancels the loop.
        if idleLoopActive, idleTriggerEnabled {
            let pattern = idlePattern
            let position = idleLoopPosition ?? MouseMover.currentPosition
            // Record where the cursor is now — if it moves during the gap,
            // the user took control and we should not restart.
            let cursorAtEnd = MouseMover.currentPosition
            DispatchQueue.main.asyncAfter(deadline: .now() + idleLoopDelay) { [weak self] in
                guard let self, self.idleTriggerEnabled, self.idleLoopActive else {
                    self?.inputMonitor.stop()
                    return
                }
                // Check if user moved the cursor during the gap.
                let cursorNow = MouseMover.currentPosition
                let dx = abs(cursorNow.x - cursorAtEnd.x)
                let dy = abs(cursorNow.y - cursorAtEnd.y)
                if dx > 2.0 || dy > 2.0 {
                    // User moved — break the loop.
                    self.idleLoopActive = false
                    self.idleLoopPosition = nil
                    self.inputMonitor.stop()
                    self.updateIdleMonitor()
                    return
                }
                self.startDanceAtPosition(pattern: pattern, position: position)
            }
        } else {
            inputMonitor.stop()
            if idleTriggerEnabled {
                idleMonitor.resetIdleTimer()
                updateIdleMonitor()
            }
        }
    }

    private func updateIdleMonitor() {
        if idleTriggerEnabled && state == .idle {
            idleMonitor.idleDelay = idleDelay
            idleMonitor.start()
        } else {
            idleMonitor.stop()
        }
    }

    /// Build a path for the given pattern, optionally starting at a specific position.
    /// When `atPosition` is nil, patterns use their default screen positioning.
    /// When provided, the path is adjusted so the animation begins at that position.
    private func buildPath(for pattern: DancePattern, atPosition position: CGPoint?) -> CursorPath? {
        let baseDuration: TimeInterval = 3.0

        switch pattern {
        case .circle:
            return GeometricPath(shape: .circle, center: position, startPosition: position, duration: baseDuration)
        case .figureEight:
            return GeometricPath(shape: .figureEight, center: position, startPosition: position, duration: baseDuration)
        case .spiral:
            return GeometricPath(shape: .spiral, center: position, startPosition: position, duration: baseDuration * 1.5)
        case .star:
            return GeometricPath(shape: .star, center: position, startPosition: position, duration: baseDuration)
        case .windowOutline:
            return WindowOutlinePath(duration: baseDuration)
        case .scribble:
            let region: CGRect?
            if let p = position {
                // Scribble in a 400×400 region around the cursor.
                region = CGRect(x: p.x - 200, y: p.y - 200, width: 400, height: 400)
            } else {
                region = nil
            }
            return ScribblePath(duration: baseDuration * 1.5, region: region, startPosition: position)
        case .handwriting:
            let text = handwritingText.isEmpty ? "hello" : handwritingText
            let charDuration = 1.2 // seconds per character — tuned against arc-length pacing
            return HandwritingPath(
                text: text,
                origin: position,
                startPosition: position,
                duration: max(2.5, Double(text.count) * charDuration)
            )
        }
    }
}
