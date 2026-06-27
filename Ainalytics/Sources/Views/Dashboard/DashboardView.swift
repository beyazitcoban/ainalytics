import SwiftUI

/// The dashboard window: a native `NavigationSplitView` — a sidebar (Overview,
/// Activity, Cost, then the enabled providers) and a large-title detail page per selection,
/// the macOS-native structure (Podcasts/Journal style). App preferences live in the
/// separate native Settings window (⌘,), not here — the dashboard is pure data.
///
/// The per-surface visuals (cards, gauges, heatmap, cost) live in the page views and
/// the shared design-system components; this file owns the navigation shell and the
/// global refresh action only.
struct DashboardView: View {
    @Environment(UsagePoller.self) private var poller
    @Environment(LogActivityState.self) private var logActivity
    @Environment(AppPreferences.self) private var preferences

    @State private var selection: DashboardSection? = .overview

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        // One refresh for the whole dashboard. A bare `.primaryAction` item clusters
        // at the detail's leading edge in NavigationSplitView (a macOS quirk), so a
        // leading `Spacer()` in a `ToolbarItemGroup` pushes it to the window's
        // trailing (right) edge. It re-polls usage AND rescans the local logs, so the
        // heatmap/cost update too — no separate per-page refresh.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Spacer()
                Button {
                    Task { await poller.refreshNow() }
                    logActivity.refresh()
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }
                .disabled(poller.isRefreshing)
                .help("Refresh now")
            }
        }
        .task { logActivity.refreshIfNeeded() }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Label {
                Text("Overview")
            } icon: {
                Image(systemName: "square.grid.2x2").foregroundStyle(.primary)
            }
            .tag(DashboardSection.overview)

            Label {
                Text("Activity")
            } icon: {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(.primary)
            }
            .tag(DashboardSection.activity)

            Label {
                Text("Cost")
            } icon: {
                Image(systemName: "dollarsign.circle").foregroundStyle(.primary)
            }
            .tag(DashboardSection.cost)

            // Providers sit at the bottom: the cross-cutting data views (Overview,
            // Activity, Cost) come first, the per-provider drill-downs below.
            Section("Providers") {
                ForEach(preferences.enabledProviderIDs, id: \.self) { id in
                    Label {
                        Text(id.displayName)
                    } icon: {
                        // Menu-bar-style mono mark (bg-less template silhouette) so the
                        // provider rows read as monochrome like the rest of the sidebar.
                        ProviderLogo(id: id, style: .mono, size: 16)
                            .foregroundStyle(.primary)
                    }
                    .tag(DashboardSection.provider(id))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 224)
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .overview {
        case .overview: OverviewPage()
        case .provider(let id): ProviderDetailPage(id: id)
        case .activity: ActivityPage()
        case .cost: CostPage()
        }
    }
}

/// The dashboard's sidebar destinations.
enum DashboardSection: Hashable {
    case overview
    case provider(ProviderID)
    case activity
    case cost
}

#if DEBUG
    #Preview("Dashboard") {
        DashboardView()
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
            .frame(width: 980, height: 740)
    }
#endif
