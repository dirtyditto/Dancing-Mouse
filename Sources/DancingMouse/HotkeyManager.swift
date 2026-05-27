import Cocoa

// MARK: - HotkeyManager
//
// Global keyboard shortcuts for triggering dance patterns. Uses NSEvent's
// global + local monitors, which is enough because we don't need to swallow
// the event globally (only locally, when our own menu has focus).
//
// Relationship with `InputMonitor`: the same key combos this class listens
// for are advertised via `hotkeyKeyCodes` / `hotkeyModifiers` so that the
// input monitor's event tap can recognize them as *intended* input and
// skip its normal "user touched the mouse/kbd → cancel" reaction.

/// Manages global hotkey registration and dispatching.
/// Hotkey combos are allowlisted in InputMonitor so they trigger patterns rather than cancelling.
final class HotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    weak var orchestrator: DanceOrchestrator?

    /// Key code constants for number keys 1-4.
    private static let key1: UInt16 = 18
    private static let key2: UInt16 = 19
    private static let key3: UInt16 = 20
    private static let key4: UInt16 = 21
    private static let keyEscape: UInt16 = 53

    init() {}

    deinit {
        stop()
    }

    /// Start listening for global hotkeys.
    func start() {
        // Monitor key events globally (when our app is NOT focused).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Also monitor locally (when our menu is open).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // swallow the event
            }
            return event
        }
    }

    /// Stop listening.
    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    /// Returns the set of key codes we handle (for InputMonitor allowlisting).
    static var hotkeyKeyCodes: Set<Int64> {
        Set([key1, key2, key3, key4, keyEscape].map { Int64($0) })
    }

    /// The modifier flags used for our hotkeys.
    static var hotkeyModifiers: CGEventFlags {
        [.maskCommand, .maskShift]
    }

    // MARK: - Event handling

    /// Returns true if the key event was handled as a hotkey.
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let orchestrator else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape — always stops, no modifier needed.
        if event.keyCode == Self.keyEscape {
            if orchestrator.state == .dancing {
                orchestrator.cancelImmediately()
                return true
            }
            return false
        }

        // ⌘⇧ + number key combos.
        guard modifiers.contains(.command), modifiers.contains(.shift) else {
            return false
        }

        switch event.keyCode {
        case Self.key1:
            orchestrator.startPattern(.circle)
            return true
        case Self.key2:
            orchestrator.startPattern(.windowOutline)
            return true
        case Self.key3:
            orchestrator.startPattern(.scribble)
            return true
        case Self.key4:
            orchestrator.startPattern(.handwriting)
            return true
        default:
            return false
        }
    }
}
