import Cocoa
import CoreGraphics

// MARK: - InputMonitor
//
// The cancel-on-input enforcer. A passive `CGEventTap` on `.cghidEventTap`
// observes every mouse and keyboard event in the system; any that is NOT
// one of our own synthetic warps (tagged by `MouseMover.syntheticTag`) and
// NOT an allowlisted hotkey (registered by `HotkeyManager`) instantly
// cancels the active dance.
//
// Threading model:
//   - The tap callback runs on its own event-tap thread.
//   - It first calls `onImmediateCancel?()` — wired in `DanceOrchestrator` to
//     flip a lock-protected flag inside `AnimationDriver`. That stops the
//     cursor from being warped on the very next tick, *without* waiting on
//     the main queue.
//   - Then it dispatches `onUserInput?()` to main for the rest of the
//     cleanup (hide trail, restore state, update UI).
//
// This split is the heart of the "the user always has ultimate control"
// guarantee: even if the main queue is jammed, the cursor stops moving.

/// Monitors all HID input via a passive CGEvent tap.
/// Any real user input (not tagged as synthetic by MouseMover) triggers an immediate cancel
/// of the active dance. **The user always has ultimate control.**
final class InputMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false

    /// Called when real (non-synthetic) user input is detected.
    var onUserInput: (() -> Void)?

    /// Called immediately from the event-tap thread (before main-queue dispatch)
    /// to set a thread-safe cancel flag. This ensures cancellation is never
    /// delayed by main-queue saturation.
    var onImmediateCancel: (() -> Void)?

    /// Key codes that are currently allowlisted (hotkey combos handled by HotkeyManager).
    /// These will NOT trigger a cancel.
    var allowlistedKeyCodes: Set<Int64> = []

    /// Modifier flags that must be present for a keyDown to be allowlisted.
    var allowlistedModifiers: CGEventFlags = []

    init() {}

    deinit {
        stop()
    }

    /// Start listening for user input. Requires Accessibility permission.
    func start() {
        guard !isRunning else { return }

        let eventMask: CGEventMask = (
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue)
        )

        // We capture `self` via the userInfo pointer.
        let unmanagedSelf = Unmanaged.passUnretained(self)

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, eventType, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                monitor.handleEvent(event, type: eventType)
                return Unmanaged.passUnretained(event)
            },
            userInfo: unmanagedSelf.toOpaque()
        )

        guard let eventTap else {
            print("[InputMonitor] Failed to create event tap — is Accessibility granted?")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
    }

    /// Stop listening.
    func stop() {
        guard isRunning else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
    }

    private func handleEvent(_ event: CGEvent, type: CGEventType) {
        // Check if this is one of our synthetic events — ignore if so.
        let userData = event.getIntegerValueField(.eventSourceUserData)
        if userData == MouseMover.syntheticTag {
            return
        }

        // For keyDown, check if it matches an allowlisted hotkey.
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            if allowlistedKeyCodes.contains(keyCode) &&
               flags.contains(allowlistedModifiers) {
                return
            }
        }

        // Real user input detected — signal cancel immediately on this thread,
        // then dispatch cleanup to main.
        onImmediateCancel?()
        DispatchQueue.main.async { [weak self] in
            self?.onUserInput?()
        }
    }
}
