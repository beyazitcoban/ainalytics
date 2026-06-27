import SwiftUI

/// "Subscription value" — is the plan worth it? Compares each provider's
/// API-equivalent usage cost (from the local log scan, monthly-normalized over the
/// history span) against the subscription price the user entered in Settings. A
/// ratio ≥ 1 means the usage would have cost more on the API than the plan.
///
/// Explicitly an estimate, not a bill: the cost is API-equivalent and the price is
/// user-supplied. Providers without a set price show a prompt rather than a number.
struct ROIView: View {
    let costs: [ProviderCost]
    let result: LogScanResult
    @Environment(AppPreferences.self) private var preferences

    /// Days the scanned activity spans (first → last active day, inclusive), the
    /// denominator for monthly normalization. At least 1 to avoid divide-by-zero.
    private var spanDays: Int {
        guard let first = result.days.first?.day, let last = result.days.last?.day else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        return max(1, days + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(costs) { providerCost in
                card(providerCost)
            }
            caption
        }
    }

    @ViewBuilder private func card(_ providerCost: ProviderCost) -> some View {
        let provider = providerCost.provider
        let planKey = preferences.selectedPlanKey(for: provider)
        let effectivePrice = PlanPriceCatalog.effectiveMonthlyPrice(
            manual: preferences.monthlyPrice(for: provider),
            provider: provider, selectedPlanKey: planKey)
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    ProviderLogo(id: provider)
                    Text(verbatim: provider.displayName)
                        .font(.headline)
                    if let plan = PlanPriceCatalog.plan(for: provider, key: planKey) {
                        Text(verbatim: plan.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let price = effectivePrice, let total = providerCost.totalUSD {
                    valueRow(monthlyCost: total * 30 / Double(spanDays), price: price)
                } else {
                    Text("Select your plan in Settings to see ROI.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func valueRow(monthlyCost: Double, price: Double) -> some View {
        let ratio = price > 0 ? monthlyCost / price : 0
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("≈ \(monthlyCost.formatted(.currency(code: "USD")))")
                    .monospacedDigit()
                Text("per month")
                Spacer(minLength: Theme.Spacing.sm)
                Text(verbatim: "vs ")
                    .foregroundStyle(.secondary)
                Text(price.formatted(.currency(code: "USD")))
                    .monospacedDigit()
            }
            .font(.callout)

            HStack(spacing: Theme.Spacing.xs) {
                Text(ratio, format: .number.precision(.fractionLength(1)))
                    + Text(verbatim: "× ")
                    + Text("value")
            }
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(ratio >= 1 ? Color.green : .secondary)
        }
    }

    private var caption: some View {
        Text("API-equivalent, monthly-normalized — vs your subscription price. An estimate, not a bill.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
    #Preview("ROI") {
        ROIView(costs: PreviewData.sampleCosts, result: PreviewData.sampleScanResult)
            .environment(PreviewData.previewPreferencesWithPrices)
            .padding()
            .frame(width: 460)
    }
#endif
