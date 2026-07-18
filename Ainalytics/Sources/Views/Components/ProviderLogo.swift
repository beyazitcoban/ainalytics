import AppKit
import SwiftUI

/// A provider's official brand mark. Two styles:
///
/// - `.color` — the provider's full-colour app-icon tile, shown wherever a provider
///   is identified in-app (dashboard cards, cost cards, the menu-bar popover rows).
/// - `.mono` — a single-colour template silhouette that adopts the surrounding tint
///   (the menu bar's light / dark / vibrancy), for the menu-bar provider mode.
///
/// Falls back to ``ProviderSwatch`` (the accent squircle) when the brand asset is
/// absent — a provider added before its logo lands, or a brand whose guidelines
/// disallow the mark — so a missing logo never blanks the UI (the Phase 11 cut-line:
/// the menu-bar mode can ship with an accent badge before logos arrive).
///
/// These official logos supersede the accent-only swatch (the kurgulama
/// "accent-evocative, not official logos" decision, reversed in the 2026-06-21
/// re-kurgulama). The provider name is always shown as text alongside, so the mark
/// is never the sole identifier (code-principles §7).
struct ProviderLogo: View {
    enum Style { case color, mono }

    let id: ProviderID
    var style: Style = .color
    var size: CGFloat = 20

    var body: some View {
        let name = Self.assetName(for: id, style: style)
        if Self.assetExists(name) {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            // No brand asset → the accent squircle keeps the provider identifiable.
            ProviderSwatch(id: id, size: size)
        }
    }

    /// Asset-catalog name for a provider's mark. The catalog slugs follow each
    /// brand's common name, with a `-color` / `-mono`
    /// suffix matching the imageset names. Also used by the menu-bar item, which
    /// renders the mono logo through the blessed `MenuBarExtra(_:image:)` path.
    static func assetName(for id: ProviderID, style: Style) -> String {
        let slug =
            switch id {
            case .claude: "claude"
            case .codex: "codex"
            }
        return "\(slug)-\(style == .color ? "color" : "mono")"
    }

    /// Whether the asset is actually bundled. Lets a provider ship before its logo
    /// (or without one, per brand guidelines) and degrade to the accent swatch
    /// instead of rendering an empty frame.
    private static func assetExists(_ name: String) -> Bool {
        NSImage(named: name) != nil
    }
}

#if DEBUG
    #Preview("Provider logos") {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                ProviderLogo(id: .claude, style: .color, size: 32)
                ProviderLogo(id: .codex, style: .color, size: 32)
            }
            HStack(spacing: 16) {
                ProviderLogo(id: .claude, style: .mono, size: 18)
                ProviderLogo(id: .codex, style: .mono, size: 18)
            }
            .foregroundStyle(.primary)
        }
        .padding()
    }
#endif
