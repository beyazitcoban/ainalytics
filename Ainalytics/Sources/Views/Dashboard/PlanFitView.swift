import SwiftData
import SwiftUI

/// "Plan fit" (right-sizing): for each provider whose plan the user has selected,
/// shows their peak utilization and projects it onto every plan of that provider —
/// so they can see whether a smaller plan would still hold their peaks, or whether
/// the current plan is right-sized.
///
/// Peak comes from accumulated `UsageSnapshot` history (the busiest window seen in
/// the last 14 days); the projection uses each plan's `relativeCapacity`. Providers
/// with no selected plan, no known-capacity plan, or no history are skipped.
struct PlanFitView: View {
    @Query private var snapshots: [UsageSnapshot]
    @Environment(AppPreferences.self) private var preferences

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .distantPast
        _snapshots = Query(
            filter: #Predicate<UsageSnapshot> { $0.capturedAt >= cutoff },
            sort: \UsageSnapshot.capturedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if applicableProviders.isEmpty {
                Text("Select your plan in Settings to see whether it's the right size.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(applicableProviders, id: \.self) { id in
                    card(for: id)
                }
            }
        }
    }

    /// Providers that have a selected, known-capacity plan and some usage history.
    private var applicableProviders: [ProviderID] {
        preferences.enabledProviderIDs.filter { id in
            guard let key = preferences.selectedPlanKey(for: id),
                let plan = PlanPriceCatalog.plan(for: id, key: key),
                plan.relativeCapacity != nil,
                peak(for: id) != nil
            else { return false }
            return true
        }
    }

    /// The peak utilization (max percent-used across this provider's windows) over
    /// the queried history, or `nil` when there are no snapshots for it.
    private func peak(for id: ProviderID) -> Double? {
        let values = snapshots
            .filter { $0.providerID == id.rawValue }
            .map { $0.limit > 0 ? min(100, $0.used / $0.limit * 100) : 0 }
        return values.max()
    }

    @ViewBuilder private func card(for id: ProviderID) -> some View {
        if let key = preferences.selectedPlanKey(for: id),
            let current = PlanPriceCatalog.plan(for: id, key: key),
            let peakValue = peak(for: id)
        {
            let results = PlanFit.results(provider: id, currentKey: key, currentPeak: peakValue)
            let recommendation = PlanFit.recommendation(
                provider: id, currentKey: key, currentPeak: peakValue)
            SurfaceCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ProviderLogo(id: id)
                        Text(verbatim: id.displayName)
                            .font(.headline)
                        Spacer()
                        Text(verbatim: current.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Peak usage")
                        Spacer()
                        Text(peakValue / 100, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    .font(.callout)

                    recommendationLine(current: current, recommendation: recommendation)

                    Divider()

                    ForEach(results) { result in
                        planRow(result)
                    }

                    Text("Based on your busiest window in the last 14 days.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func recommendationLine(
        current: PlanOption, recommendation: PlanOption?
    ) -> some View {
        if let recommendation,
            let recCap = recommendation.relativeCapacity, let curCap = current.relativeCapacity,
            recCap < curCap
        {
            Label {
                Text("You could switch to \(recommendation.displayName).")
            } icon: {
                Image(systemName: "arrow.down.circle.fill")
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.green)
        } else {
            Label {
                Text("Right-sized — a smaller plan couldn't hold your peaks.")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func planRow(_ result: PlanFitResult) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: Self.symbol(for: result.verdict))
                .foregroundStyle(Self.color(for: result.verdict))
                .accessibilityLabel(Self.accessibilityLabel(for: result.verdict))
            Text(verbatim: result.plan.displayName)
            if result.isCurrent {
                Text("Current")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(result.projectedPeak / 100, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .foregroundStyle(Self.color(for: result.verdict))
        }
        .font(.callout)
    }

    private static func symbol(for verdict: PlanFitVerdict) -> String {
        switch verdict {
        case .fits: "checkmark.circle.fill"
        case .tight: "exclamationmark.circle.fill"
        case .over: "xmark.circle.fill"
        }
    }

    private static func color(for verdict: PlanFitVerdict) -> Color {
        switch verdict {
        case .fits: .green
        case .tight: .orange
        case .over: .secondary
        }
    }

    private static func accessibilityLabel(for verdict: PlanFitVerdict) -> LocalizedStringKey {
        switch verdict {
        case .fits: "Fits"
        case .tight: "Tight"
        case .over: "Over limit"
        }
    }
}

#if DEBUG
    #Preview("Plan fit") {
        PlanFitView()
            .environment(PreviewData.previewPreferencesWithPrices)
            .padding()
            .frame(width: 460)
            .modelContainer(PreviewContainers.seeded)
    }
#endif
