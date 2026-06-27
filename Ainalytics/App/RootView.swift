import SwiftUI

/// Dashboard window root — hosts the live `DashboardView` (Phase 4: live limits,
/// renewal dates, the most-active model, and snapshot-fed usage trends). The
/// Phase 5 log engine adds the historical heatmap and cost comparison.
struct RootView: View {
    var body: some View {
        DashboardView()
    }
}

#if DEBUG
    #Preview {
        RootView()
            .environment(AppState.preview(PreviewData.mixedRuntimes))
            .environment(AppPreferences())
            .environment(
                UsagePoller(
                    appState: AppState(), preferences: AppPreferences(),
                    modelContext: PreviewContainers.seeded.mainContext)
            )
            .environment(
                LogActivityState.preview(
                    result: PreviewData.sampleScanResult, costs: PreviewData.sampleCosts)
            )
            .modelContainer(PreviewContainers.seeded)
    }
#endif
