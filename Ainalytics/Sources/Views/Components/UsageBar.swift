import SwiftUI

/// A refined capsule usage indicator — the design-system replacement for a raw
/// `ProgressView` bar. A faint capsule track holds a tinted fill whose colour
/// follows usage severity (provider accent → amber → red, via `Theme.usageTint`).
/// Built for reuse across the menu bar and the dashboard. The numeric percent lives
/// in the surrounding row, so the bar itself stays decorative (`accessibilityHidden`).
struct UsageBar: View {
    /// How much of the window is consumed, expected 0...100.
    let percentUsed: Double
    /// The provider's accent — the bar's tint while there is still headroom.
    let accent: Color
    var height: CGFloat = 6

    /// The bar fills with what *remains*, not what is used: a full bar means plenty of
    /// headroom and it drains as the window is consumed — so "full + green = good,
    /// draining + red = bad" points the same way as the "% left" label beside it.
    private var remainingFraction: Double { min(1, max(0, (100 - percentUsed) / 100)) }
    private var tint: Color { Theme.usageTint(percentUsed: percentUsed, accent: accent) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.quaternary)
                Capsule(style: .continuous)
                    .fill(tint.gradient)
                    // While any headroom remains, never narrower than the bar is tall, so
                    // even ~1% left reads as a rounded nub rather than vanishing; a fully
                    // consumed window (0% left) shows an empty track.
                    .frame(
                        width: remainingFraction > 0
                            ? max(height, geo.size.width * remainingFraction) : 0)
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.4), value: remainingFraction)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("UsageBar — severity ramp") {
        VStack(spacing: 16) {
            UsageBar(percentUsed: 24, accent: Theme.accent(for: .claude))
            UsageBar(percentUsed: 83, accent: Theme.accent(for: .codex))
        }
        .padding()
        .frame(width: 260)
    }
#endif
