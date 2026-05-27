import Foundation

// MARK: - Easing
//
// Pure mathematical curves that reshape the normalized time `t` ∈ [0, 1]
// before it's passed to a `CursorPath`. The result is still in [0, 1] but
// the cursor speed along the path is no longer constant.
//
// Picked by the user via the "Easing" picker in the menu UI; the chosen
// preset's `function` is handed to `AnimationDriver.start(...)`.
// Reference: <https://easings.net/> for visualizations of each curve.

/// Pure easing functions mapping [0,1] → [0,1].
enum Easing {
    /// Smooth acceleration then deceleration (cubic).
    static func easeInOutCubic(_ t: Double) -> Double {
        t < 0.5
            ? 4.0 * t * t * t
            : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0
    }

    /// Smoother ease in/out (quintic) — more dramatic slow-fast-slow.
    static func easeInOutQuintic(_ t: Double) -> Double {
        t < 0.5
            ? 16.0 * t * t * t * t * t
            : 1.0 - pow(-2.0 * t + 2.0, 5.0) / 2.0
    }

    /// Classic Hermite smoothstep.
    static func smoothstep(_ t: Double) -> Double {
        let c = max(0, min(1, t))
        return c * c * (3.0 - 2.0 * c)
    }

    /// Sine-based ease in/out — gentle, wave-like.
    static func easeInOutSine(_ t: Double) -> Double {
        -(cos(Double.pi * t) - 1.0) / 2.0
    }

    /// Linear (no easing).
    static func linear(_ t: Double) -> Double { t }
}

/// Named easing presets for UI selection.
enum EasingPreset: String, CaseIterable, Identifiable {
    case linear = "Linear"
    case smoothstep = "Smoothstep"
    case cubic = "Ease In/Out Cubic"
    case quintic = "Ease In/Out Quintic"
    case sine = "Ease In/Out Sine"

    var id: String { rawValue }

    var function: (Double) -> Double {
        switch self {
        case .linear:    return Easing.linear
        case .smoothstep: return Easing.smoothstep
        case .cubic:     return Easing.easeInOutCubic
        case .quintic:   return Easing.easeInOutQuintic
        case .sine:      return Easing.easeInOutSine
        }
    }
}
