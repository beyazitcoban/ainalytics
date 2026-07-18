import SwiftUI

/// Canonical brand + usage-severity colours, shared between the main app (`Theme`)
/// and the widget extension. Keyed by `ProviderID.rawValue` (a `String`) rather
/// than `ProviderID` so the widget target can render provider identity without
/// importing the app's provider layer. This is the single source of truth for the
/// accent RGBs and the severity tints — `Theme` delegates to it (DRY).
enum SharedBrand {

    /// RGB components (0–1) for a provider's accent, by `ProviderID.rawValue`.
    /// A neutral grey is the fallback for an unrecognized id (never hit for the
    /// three shipping providers; keeps the lookup total without a `ProviderID`).
    static func accentComponents(forProviderRaw raw: String) -> (red: Double, green: Double, blue: Double) {
        switch raw {
        case "claude": (0.843, 0.463, 0.333)  // #D77655 — Anthropic clay
        case "codex": (0.224, 0.255, 1.0)  // #3941FF — Codex indigo-blue
        default: (0.55, 0.55, 0.55)  // neutral fallback
        }
    }

    /// A provider's accent colour, by `ProviderID.rawValue`.
    static func accent(forProviderRaw raw: String) -> Color {
        let c = accentComponents(forProviderRaw: raw)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    /// Usage-severity accents (amber → red as a window nears its limit). The numeric
    /// percent is always shown alongside, so the cue is never colour-only.
    static let warning = Color(red: 0.92, green: 0.62, blue: 0.18)  // amber
    static let critical = Color(red: 0.86, green: 0.31, blue: 0.27)  // red

    /// The six-stop usage-severity ramp, keyed by how much of a window *remains*: full
    /// green when there is plenty of headroom, sliding through lime / yellow / amber /
    /// orange to red as the window empties. Stepped (not continuous) so each band stays
    /// a legible "how worried should I be" signal rather than a muddy gradient. Entries
    /// are upper bounds on `percentUsed`, ascending.
    private static let severityRamp: [(maxUsed: Double, color: Color)] = [
        (25, Color(red: 0.188, green: 0.753, blue: 0.306)),  // ≥75% left — bright green
        (45, Color(red: 0.525, green: 0.761, blue: 0.196)),  // 55–75% left — lime
        (60, Color(red: 0.878, green: 0.773, blue: 0.129)),  // 40–55% left — yellow
        (75, Color(red: 0.941, green: 0.659, blue: 0.157)),  // 25–40% left — amber
        (88, Color(red: 0.933, green: 0.478, blue: 0.188)),  // 12–25% left — orange
        (.infinity, Color(red: 0.859, green: 0.310, blue: 0.271)),  // <12% left — red
    ]

    /// Severity tint for a window that is `percentUsed` consumed (0...100). The colour now
    /// depends only on severity — the provider's accent identifies it in the logo/name,
    /// not in the bar — so `accent` is kept for call-site/API compatibility (the dashboard
    /// Gauge + widget pass it through) but no longer tints the bar; it retires when the
    /// dashboard fill is reworked.
    static func usageTint(percentUsed: Double, accent: Color) -> Color {
        severityRamp.first { percentUsed < $0.maxUsed }?.color ?? critical
    }

    /// Convenience for the widget: the severity tint for a provider's usage in one
    /// call (accent resolved from the raw provider id).
    static func usageTint(percentUsed: Double, providerRaw raw: String) -> Color {
        usageTint(percentUsed: percentUsed, accent: accent(forProviderRaw: raw))
    }
}
