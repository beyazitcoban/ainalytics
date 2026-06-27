import AppKit
import SwiftUI

/// Visual identity tokens — the kurgulama "identity mini-pass" (code side).
/// These colors ARE the palette definition (the single source of truth); the
/// real app icon is authored separately in Icon Composer (Beyazıt's step).
enum Theme {

    /// Per-provider accent — brand-evocative, not the providers' official logos.
    /// The RGBs live in `SharedBrand` (the single source of truth shared with the
    /// widget extension); `Theme` delegates so the app and widget never drift.
    static func accent(for id: ProviderID) -> Color {
        SharedBrand.accent(forProviderRaw: id.rawValue)
    }

    /// GitHub-style activity heatmap ramp, low → high intensity. Consumed by the
    /// dashboard heatmap (Phase 4/5); defined here as part of the identity pass.
    /// The four activity steps read well on both appearances; only the "no
    /// activity" base must adapt — a single dark-tuned value reads as heavy black
    /// squares on a light dashboard.
    static let heatmapRamp: [Color] = [
        heatmapEmpty,  // no activity (appearance-adaptive)
        Color(red: 0.11, green: 0.30, blue: 0.24),
        Color(red: 0.14, green: 0.48, blue: 0.34),
        Color(red: 0.20, green: 0.68, blue: 0.44),
        Color(red: 0.34, green: 0.88, blue: 0.55),  // peak
    ]

    /// The empty-day cell: a faint translucent white. Because the windows are
    /// translucent (the macOS background is tinted by the wallpaper), a fixed grey
    /// read badly in both appearances; an additive white at low opacity lightens
    /// whatever sits behind it consistently, so the empty cell stays subtle and
    /// uniform on light and dark alike, and never dominates as a solid block.
    static let heatmapEmpty = Color.white.opacity(0.1)
}

// MARK: - Design system (Liquid Glass pass)
//
// These tokens were introduced with the Tahoe-native Liquid Glass design pass so
// every surface breathes on one grid and shares one radius/severity language,
// instead of scattering magic numbers across views.

extension Theme {

    /// Spacing rhythm — one small scale used in place of inline magic numbers.
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    /// Card corner radius — the rounded-rect radius used across surfaces.
    /// Pill shapes are expressed via `Capsule`, not a number.
    enum Radius {
        static let card: CGFloat = 16
    }

    /// Usage-severity accents. The usage bar wears the provider's own accent while
    /// there is headroom, then shifts to amber and red as the limit nears — so colour
    /// itself becomes the at-a-glance "near the limit" signal. The numeric percent is
    /// always shown alongside, so the cue is never colour-only (code-principles §7).
    /// The severity accents + the tint mapping live in `SharedBrand` (shared with the
    /// widget); `Theme` re-exposes them so existing call sites stay `Theme.*`.
    static let warning = SharedBrand.warning  // amber
    static let critical = SharedBrand.critical  // red

    /// Maps how much of a window is consumed (0...100) to its indicator tint.
    static func usageTint(percentUsed: Double, accent: Color) -> Color {
        SharedBrand.usageTint(percentUsed: percentUsed, accent: accent)
    }
}
