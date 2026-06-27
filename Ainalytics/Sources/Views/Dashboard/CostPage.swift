import SwiftUI

/// The "Cost" page — the API-equivalent cost comparison across providers from the
/// local log scan, with an empty state until a scan finds priced models.
struct CostPage: View {
    @Environment(LogActivityState.self) private var logActivity

    var body: some View {
        DashboardPage(title: Text("Cost")) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                // Plan fit (right-sizing) is independent of the cost scan — it needs
                // only the selected plan + usage history — so it shows regardless of
                // whether priced models were found.
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Plan fit")
                        .font(.title3.weight(.semibold))
                    PlanFitView()
                }

                if logActivity.costs.isEmpty {
                    ContentUnavailableView {
                        Label("No cost data yet", systemImage: "dollarsign.circle")
                    } description: {
                        Text("Cost appears once a log scan finds models with a known price.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Subscription value")
                            .font(.title3.weight(.semibold))
                        ROIView(costs: logActivity.costs, result: logActivity.result)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("API-equivalent cost")
                            .font(.title3.weight(.semibold))
                        CostSummaryView(costs: logActivity.costs)
                    }
                }
            }
        }
    }
}
