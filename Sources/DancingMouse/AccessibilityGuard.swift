import Cocoa

// MARK: - AccessibilityGuard
//
// Dancing Mouse needs two Accessibility (AX) capabilities:
//   - Move the cursor (`CGWarpMouseCursorPosition` via `MouseMover`)
//   - Listen to global input (`CGEvent.tapCreate` via `InputMonitor`)
//
// Both require the app to be listed in System Settings → Privacy & Security →
// Accessibility. This file handles the first-launch prompt and surfaces a
// friendly alert if the system dialog is dismissed.

/// Checks whether Accessibility permission is granted and prompts the user if not.
enum AccessibilityGuard {
    /// Returns `true` if the app is trusted for Accessibility.
    /// When `promptIfNeeded` is true and the app is NOT trusted, macOS will show
    /// the system prompt asking the user to grant permission in System Settings.
    @discardableResult
    static func ensureAccessibility(promptIfNeeded: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): promptIfNeeded] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            showAccessibilityAlert()
        }
        return trusted
    }

    private static func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            Dancing Mouse needs Accessibility permission to move the cursor \
            and detect user input.

            Please open System Settings → Privacy & Security → Accessibility \
            and enable Dancing Mouse.

            The app will work once permission is granted (you may need to relaunch).
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
