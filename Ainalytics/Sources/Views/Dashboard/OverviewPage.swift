import SwiftUI

/// The "Overview" page — every enabled provider's usage card plus the snapshot-fed
/// usage trend. Per-provider, activity, and cost detail live on their own sidebar
/// pages; this is the at-a-glance summary.
struct OverviewPage: View {
    @Environment(AppState.self) private var appState
    @Environment(LogActivityState.self) private var logActivity
    @Environment(AppPreferences.self) private var preferences

    private let cardColumns = [
        GridItem(.adaptive(minimum: 300), spacing: Theme.Spacing.lg, alignment: .top)
    ]

    var body: some View {
        DashboardPage(
            title: Text("Overview"),
            subtitle: appState.lastUpdated.map {
                Text("Updated") + Text(verbatim: " ") + Text($0, style: .relative)
            }
        ) {
            LazyVGrid(columns: cardColumns, alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(preferences.enabledProviderIDs, id: \.self) { id in
                    ProviderUsageCard(
                        id: id, runtime: appState.runtime(for: id),
                        mostUsedModel: logActivity.result.mostUsedModel(for: id)?.model)
                }
            }
            if !preferences.enabledProviderIDs.isEmpty {
                forecastSection
            }
            trendSection
        }
    }

    private var forecastSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Forecast")
                .font(.title3.weight(.semibold))
            BurnRateView(providers: preferences.enabledProviderIDs)
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Daily usage")
                .font(.title3.weight(.semibold))
            SurfaceCard {
                UsageTrendChart()
                    .frame(height: 240)
            }
        }
    }
}
