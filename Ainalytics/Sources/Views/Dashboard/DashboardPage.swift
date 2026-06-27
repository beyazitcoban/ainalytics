import SwiftUI

/// Shared scaffold for the dashboard's detail column — a large navigation title
/// (the native macOS pattern, like Podcasts/Journal) with an optional secondary
/// subtitle, over a scrolling content area on the shared spacing grid. Pages supply
/// their own content; the title also drives the window's `navigationTitle`.
struct DashboardPage<Content: View>: View {
    let title: Text
    var subtitle: Text? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    title
                        .font(.largeTitle.weight(.semibold))
                    if let subtitle {
                        subtitle
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                content
            }
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        // The visible title lives in the content as a large header (native
        // Podcasts/Journal pattern); drop the duplicate from the title bar but keep
        // the window's logical title for the window menu and accessibility.
        .toolbar(removing: .title)
    }
}
