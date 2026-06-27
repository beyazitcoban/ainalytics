import SwiftUI

/// A grouped-content surface — the dashboard's card container. A refined material
/// fill on the concentric card radius with token padding and a hairline separator,
/// replacing the repeated inline `controlBackgroundColor` + stroke treatments.
///
/// Liquid Glass is deliberately reserved for the floating controls (buttons,
/// toolbars); content panels sit on this calmer material surface, which is the
/// native idiom — wrapping every panel in glass reads as gimmick, not Tahoe.
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.lg
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(.separator.opacity(0.5), lineWidth: 1))
    }
}
