import SwiftUI

/// Per-provider "what this usage would have cost via the API" — the Phase 5 cost
/// comparison. It is explicitly an API-equivalent estimate from local token logs,
/// not the user's subscription price; the caption says so, and a model with no
/// known price shows "—" rather than a guessed figure.
struct CostSummaryView: View {
    let costs: [ProviderCost]

    private var anyUnpriced: Bool { costs.contains { $0.hasUnpricedModels } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(costs) { providerCost in
                card(providerCost)
            }
            caption
        }
    }

    private func card(_ providerCost: ProviderCost) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    ProviderLogo(id: providerCost.provider)
                    Text(providerCost.provider.displayName)
                        .font(.headline)
                    Spacer()
                    totalLabel(providerCost.totalUSD)
                }
                ForEach(providerCost.models) { modelCost in
                    modelRow(modelCost)
                }
            }
        }
    }

    private func totalLabel(_ usd: Double?) -> some View {
        Group {
            if let usd {
                Text("≈ \(usd.formatted(.currency(code: "USD")))")
            } else {
                Text(verbatim: "—")
            }
        }
        .font(.headline)
        .monospacedDigit()
    }

    private func modelRow(_ modelCost: ModelCost) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: modelCost.usage.model)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text(modelCost.usage.totalTokens, format: .number.notation(.compactName))
                Text("tokens")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            costLabel(modelCost.usd)
                .font(.callout)
                .monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
        }
    }

    @ViewBuilder private func costLabel(_ usd: Double?) -> some View {
        if let usd {
            Text(usd, format: .currency(code: "USD"))
        } else {
            Text(verbatim: "—").foregroundStyle(.secondary)
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Estimated cost if this usage were billed via each provider's API — not your subscription price.")
            if anyUnpriced {
                Text("\u{2014} shown when a model's price is unavailable.")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

#if DEBUG
    #Preview("Cost summary") {
        CostSummaryView(costs: PreviewData.sampleCosts)
            .padding()
            .frame(width: 420)
    }
#endif
