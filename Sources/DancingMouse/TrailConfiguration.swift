import SwiftUI

// MARK: - TrailConfiguration
//
// Observable settings object for the cursor ghost trail. Bound directly to
// SwiftUI controls in `DancingMouseApp.swift`, and read every frame by
// `CursorTrailRenderer` — so editing a slider while a dance is running
// updates the rendered trail live.

/// Fade style for the cursor ghost trail.
enum TrailFadeStyle: String, CaseIterable, Identifiable {
    case linear = "Linear"
    case exponential = "Exponential"

    var id: String { rawValue }

    /// Returns opacity for a point at `index` out of `total` points (0 = newest, total-1 = oldest).
    func opacity(at index: Int, total: Int) -> Double {
        guard total > 1 else { return 1.0 }
        let normalized = Double(index) / Double(total - 1) // 0 = newest, 1 = oldest
        switch self {
        case .linear:
            return 1.0 - normalized
        case .exponential:
            return pow(1.0 - normalized, 2.5)
        }
    }
}

/// Named color presets for the trail.
enum TrailColorPreset: String, CaseIterable, Identifiable {
    case ethereal = "Ethereal"
    case neon = "Neon"
    case fire = "Fire"
    case custom = "Custom"

    var id: String { rawValue }

    var color: NSColor {
        switch self {
        case .ethereal: return .white
        case .neon:     return NSColor(red: 0.1, green: 0.9, blue: 1.0, alpha: 1.0)
        case .fire:     return NSColor(red: 1.0, green: 0.4, blue: 0.1, alpha: 1.0)
        case .custom:   return .systemBlue
        }
    }
}

/// Configuration model for the cursor ghost/trail effect.
@Observable
final class TrailConfiguration {
    var enabled: Bool = true
    var length: Int = 40           // ring buffer size: 5–50
    var colorPreset: TrailColorPreset = .ethereal
    var customColor: NSColor = .systemBlue
    var opacity: Double = 0.8      // max opacity of newest dot
    var fadeStyle: TrailFadeStyle = .exponential
    var dotSize: CGFloat = 10.0    // diameter of newest dot

    /// The effective trail color based on preset selection.
    var effectiveColor: NSColor {
        colorPreset == .custom ? customColor : colorPreset.color
    }
}
