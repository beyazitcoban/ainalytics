import SwiftUI

/// A single provider's detail page — its usage card (windows, renewal, most-used
/// model) and, when a log scan has priced models for it, its API-equivalent cost.
struct ProviderDetailPage: View {
    let id: ProviderID
    @Environment(AppState.self) private var appState
    @Environment(LogActivityState.self) private var logActivity

    var body: some View {
        DashboardPage(
            title: Text(verbatim: id.displayName),
            subtitle: appState.lastUpdated.map {
                Text("Updated") + Text(verbatim: " ") + Text($0, style: .relative)
            }
        ) {
            ProviderUsageCard(
                id: id, runtime: appState.runtime(for: id),
                mostUsedModel: logActivity.result.mostUsedModel(for: id)?.model)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Forecast")
                    .font(.title3.weight(.semibold))
                BurnRateView(providers: [id])
            }

            if let cost = logActivity.costs.first(where: { $0.provider == id }) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("API-equivalent cost")
                        .font(.title3.weight(.semibold))
                    CostSummaryView(costs: [cost])
                }
            }
        }
    }
}
