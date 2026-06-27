import SwiftUI

/// The provider's brand swatch — an accent-filled squircle shown wherever a provider
/// is identified (menu-bar row, dashboard card, cost card). Replaces the earlier
/// generic accent dot. Deliberately accent-evocative, not the provider's official
/// logo (the kurgulama decision); optional brand logos are a later, separate feature.
struct ProviderSwatch: View {
    let id: ProviderID
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Theme.accent(for: id).gradient)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Swatches") {
        HStack(spacing: 12) {
            ProviderSwatch(id: .claude)
            ProviderSwatch(id: .codex, size: 32)
        }
        .padding()
    }
#endif
