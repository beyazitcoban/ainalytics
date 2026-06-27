import SwiftUI

/// The "Activity" page — the per-day GitHub-style heatmap from the local CLI logs,
/// followed (once loaded) by the Phase 10 insight cards: activity patterns (streak
/// + peak hours) and per-provider consumption insights. Scanning / empty / error
/// states are handled below. Rescanning is driven by the dashboard's single
/// global Refresh button (it re-polls usage AND rescans logs) — no per-page button.
struct ActivityPage: View {
    @Environment(LogActivityState.self) private var logActivity

    var body: some View {
        DashboardPage(title: Text("Activity")) {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch logActivity.phase {
        case .idle, .scanning:
            SurfaceCard {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Scanning logs…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        case .failed(let message):
            SurfaceCard {
                ContentUnavailableView {
                    Label("Couldn't read logs", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(verbatim: message)
                }
            }
        case .loaded:
            if logActivity.result.days.isEmpty {
                SurfaceCard {
                    ContentUnavailableView {
                        Label("No local logs found", systemImage: "tray")
                    } description: {
                        Text("Activity appears here once your Claude or Codex CLI has session logs.")
                    }
                }
            } else {
                VStack(spacing: Theme.Spacing.lg) {
                    SurfaceCard {
                        ActivityHeatmap(days: logActivity.result.days)
                    }
                    ActivityPatternsView(insights: logActivity.insights)
                    ConsumptionInsightsView(insights: logActivity.insights.consumption)
                }
            }
        }
    }
}
