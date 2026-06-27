import SwiftUI

/// The menu-bar item's label when a provider is pinned (Settings → General → Menu Bar):
/// the provider's monochrome logo and/or its most-constrained window's remaining usage,
/// rendered per the chosen ``MenuBarStyle``. Composes existing primitives (``ProviderLogo``
/// + `Text`) — it is not a new design-system component.
///
/// The percentage is **locale-formatted** (`.formatted(.percent)`), so the `%` sits where
/// the language puts it (tr "%90", en "90%"). The mono logo is the menu bar's 16-pt
/// intrinsic size.
///
/// Rendered through `MenuBarExtra(content:label:)`: SwiftUI converts this label to the
/// status-item image. (The Phase 11 "blob" was the 360-pt asset intrinsic size — since
/// fixed to 16 pt — not the custom label itself.)
struct MenuBarLabel: View {
    let provider: ProviderID
    let runtime: ProviderRuntime
    let style: MenuBarStyle

    private static let logoSize: CGFloat = 16

    var body: some View {
        let percent = percentText
        let showLogo = style != .percentOnly || percent == nil
        HStack(spacing: 0) {
            // Always show the logo, except for `.percentOnly` when a percentage exists —
            // and even then fall back to the logo so the menu bar is never empty.
            if showLogo {
                ProviderLogo(id: provider, style: .mono, size: Self.logoSize)
            }
            if let trailing = trailingText(percent) {
                // The logo↔text gap is *leading whitespace in the text*, NOT HStack
                // `spacing`: SwiftUI maps a MenuBarExtra label's Image → the status-item
                // button image and its Text → the button title, so inter-element spacing is
                // the system's fixed image–title gap and only space inside the title widens
                // it. Two spaces ≈ a comfortable gap at the menu-bar font size.
                Text(verbatim: showLogo ? "  \(trailing)" : trailing)
                    .monospacedDigit()
            }
        }
    }

    /// The text shown after the logo, per style. `.logoNamePercent` combines the provider
    /// name and the percentage in a *single* `Text` — two separate `Text`s could drop the
    /// trailing one when SwiftUI converts the label to the menu-bar status-item image.
    private func trailingText(_ percent: String?) -> String? {
        switch style {
        case .percentOnly, .logoPercent:
            return percent
        case .logoNamePercent:
            guard let percent else { return provider.displayName }
            return "\(provider.displayName) \(percent)"
        }
    }

    /// The most-constrained (binding) window's remaining percentage, locale-formatted
    /// (tr "%90", en "90%"). `nil` when the provider has no usable window (not connected
    /// / degraded) — the menu bar then shows just the logo.
    private var percentText: String? {
        guard let window = runtime.primaryWindow else { return nil }
        return (window.percentRemaining / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}
