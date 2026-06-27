import SwiftData
import SwiftUI

/// "Forecast" — a burn-rate run-out projection per provider, derived from the
/// accumulated `UsageSnapshot` history (the same snapshot source the trend chart
/// uses) by the pure `PredictionEngine`. One row per provider: its most urgent
/// window's projection, tinted by severity. Honest about thin history — a window
/// with too few readings reads "collecting forecast data…", never a fake number.
struct BurnRateView: View {
    let providers: [ProviderID]
    @Query private var snapshots: [UsageSnapshot]

    init(providers: [ProviderID]) {
        self.providers = providers
        // A monthly window needs ~30 days of history to project; bound the query
        // there (keep-all retention is still deferred, ARCHITECTURE §11).
        let cutoff = Calendar.current.date(byAdding: .day, value: -35, to: .now) ?? .distantPast
        _snapshots = Query(
            filter: #Predicate<UsageSnapshot> { $0.capturedAt >= cutoff },
            sort: \UsageSnapshot.capturedAt)
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(providers, id: \.self) { id in
                    row(for: id)
                }
            }
        }
    }

    private func row(for id: ProviderID) -> some View {
        let forecast = forecast(for: id)
        // Center-align logo + name (matching the Consumption and ROI cards) — a
        // baseline alignment floats the logo above the name and broke the symmetry
        // across the dashboard's provider headers.
        return HStack(spacing: Theme.Spacing.sm) {
            ProviderLogo(id: id)
            Text(verbatim: id.displayName)
                .font(.headline)
            Spacer(minLength: Theme.Spacing.sm)
            forecastLabel(forecast)
        }
    }

    @ViewBuilder private func forecastLabel(_ forecast: BurnRateForecast) -> some View {
        switch forecast {
        case .insufficientData:
            Text("Collecting forecast data…")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .onTrack:
            Label {
                Text("On track — not on pace to run out this cycle.")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.callout)
            .foregroundStyle(.green)
            .labelStyle(.titleAndIcon)
        case let .willRunOut(date, beforeReset):
            if beforeReset {
                (Text("Projected to run out") + Text(verbatim: " ") + Text(date, style: .relative))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.critical)
            } else {
                Text("Resets before you'd run out.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Build per-window forecasts for one provider from its snapshot history and
    /// reduce to the most urgent.
    private func forecast(for id: ProviderID) -> BurnRateForecast {
        let mine = snapshots.filter { $0.providerID == id.rawValue }
        guard !mine.isEmpty else { return .insufficientData }

        let byWindow = Dictionary(grouping: mine, by: \.windowTypeRaw)
        let perWindow: [BurnRateForecast] = byWindow.values.map { windowSnapshots in
            let ordered = windowSnapshots.sorted { $0.capturedAt < $1.capturedAt }
            let points = ordered.map {
                BurnPoint(
                    date: $0.capturedAt,
                    percent: $0.limit > 0 ? min(100, $0.used / $0.limit * 100) : 0)
            }
            return PredictionEngine.forecast(points: points, resetsAt: ordered.last?.resetsAt)
        }
        return PredictionEngine.mostUrgent(perWindow)
    }
}

#if DEBUG
    #Preview("Forecast — seeded") {
        BurnRateView(providers: [.claude, .codex])
            .padding()
            .frame(width: 460)
            .modelContainer(PreviewContainers.burnRate)
    }
#endif
