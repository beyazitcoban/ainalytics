import SwiftUI

/// "Consumption" — *what* you consume, per provider, from the local CLI logs
/// (Phase 10): the model mix (each model's share of tokens), the cache-hit ratio
/// (fraction of input served from cache), and the input/output token balance.
/// Derived by `InsightsEngine` from the same scan as the cost view; framed plainly
/// as local-log figures, with a localized "Other" folding the long tail and no
/// fabricated numbers (a model with no data simply does not appear).
struct ConsumptionInsightsView: View {
    let insights: [ConsumptionInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(insights.filter(\.hasData)) { insight in
                card(insight)
            }
            Text("Derived from your local CLI logs — message content is never read.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func card(_ insight: ConsumptionInsight) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    ProviderLogo(id: insight.provider)
                    Text(verbatim: insight.provider.displayName).font(.headline)
                }
                if !insight.modelMix.isEmpty {
                    modelMix(insight)
                }
                metrics(insight)
            }
        }
    }

    // MARK: - Model mix

    private func modelMix(_ insight: ConsumptionInsight) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Model mix").font(.subheadline.weight(.medium))
            proportionBar(insight)
            ForEach(Array(insight.modelMix.enumerated()), id: \.element.id) { index, share in
                HStack(spacing: Theme.Spacing.sm) {
                    Circle()
                        .fill(mixColor(insight.provider, index: index))
                        .frame(width: 8, height: 8)
                    Text(verbatim: share.isOther ? String(localized: "Other") : share.model)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Theme.Spacing.sm)
                    Text(share.share, format: .percent.precision(.fractionLength(0)))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func proportionBar(_ insight: ConsumptionInsight) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(Array(insight.modelMix.enumerated()), id: \.element.id) { index, share in
                    Rectangle()
                        .fill(mixColor(insight.provider, index: index))
                        .frame(width: max(2, geometry.size.width * share.share))
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }

    // MARK: - Cache hit + input/output

    private func metrics(_ insight: ConsumptionInsight) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            if let ratio = insight.cacheHitRatio {
                stat(
                    title: "Cache hit rate",
                    value: ratio.formatted(.percent.precision(.fractionLength(0))))
            }
            stat(title: "Input / Output", value: inputOutputLabel(insight))
        }
    }

    private func stat(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.headline).monospacedDigit()
        }
    }

    private func inputOutputLabel(_ insight: ConsumptionInsight) -> String {
        let input = insight.inputTokens.formatted(.number.notation(.compactName))
        let output = insight.outputTokens.formatted(.number.notation(.compactName))
        return "\(input) / \(output)"
    }

    /// Steps the provider's own accent lighter for each successive model slice, so
    /// the whole mix bar reads as one provider's palette rather than a rainbow.
    private func mixColor(_ provider: ProviderID, index: Int) -> Color {
        Theme.accent(for: provider).opacity(max(0.35, 1.0 - Double(index) * 0.18))
    }
}

#if DEBUG
    #Preview("Consumption — seeded") {
        ConsumptionInsightsView(
            insights: InsightsEngine.consumption(models: PreviewData.sampleScanResult.models)
        )
        .padding()
        .frame(width: 460)
    }
#endif
