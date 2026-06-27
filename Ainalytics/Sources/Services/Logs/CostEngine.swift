import Foundation

/// The API-equivalent cost of one model's usage. `usd` is `nil` when the model's
/// price is unknown — shown as "—", never a guessed figure.
struct ModelCost: Sendable, Identifiable {
    let usage: ModelUsage
    let usd: Double?

    var id: String { usage.id }
}

/// One provider's API-equivalent cost: its per-model breakdown plus a total over
/// the priced models.
struct ProviderCost: Sendable, Identifiable {
    let provider: ProviderID
    let models: [ModelCost]

    var id: ProviderID { provider }

    /// Sum over the models that could be priced. `nil` only when none could be
    /// priced (so the UI shows "—" instead of a misleading $0.00).
    var totalUSD: Double? {
        let priced = models.compactMap(\.usd)
        return priced.isEmpty ? nil : priced.reduce(0, +)
    }

    /// True when at least one model could not be priced — surfaced as a footnote
    /// so a low total is not mistaken for complete.
    var hasUnpricedModels: Bool { models.contains { $0.usd == nil } }
}

/// Turns scanned token counts into "what this would have cost via each provider's
/// API" (ARCHITECTURE §2 CostEngine). It is explicitly an API-equivalent estimate,
/// not the user's subscription price — the UI labels it as such.
enum CostEngine {
    /// Price every model in the scan, grouped by provider, ordered by spend.
    static func costs(for result: LogScanResult, using catalog: ModelPriceCatalog) async
        -> [ProviderCost]
    {
        var byProvider: [ProviderID: [ModelCost]] = [:]
        for usage in result.models {
            let price = await catalog.price(for: usage.provider, model: usage.model)
            let usd: Double? = price.map { cost(of: usage, at: $0) }
            byProvider[usage.provider, default: []].append(ModelCost(usage: usage, usd: usd))
        }

        var providerCosts: [ProviderCost] = []
        for (provider, models) in byProvider {
            let ordered = models.sorted { $0.usage.totalTokens > $1.usage.totalTokens }
            providerCosts.append(ProviderCost(provider: provider, models: ordered))
        }
        return providerCosts.sorted { ($0.totalUSD ?? 0) > ($1.totalUSD ?? 0) }
    }

    /// tokens ÷ 1M × per-MTok rate, summed over the four token classes. Cache rates
    /// fall back to the input rate when the catalog omits them (a slight over-
    /// estimate, consistent with the "estimate" framing).
    private static func cost(of usage: ModelUsage, at price: ModelPrice) -> Double {
        let perMillion = 1_000_000.0
        let input = Double(usage.inputTokens) / perMillion * price.input
        let output = Double(usage.outputTokens) / perMillion * price.output
        let cacheRead = Double(usage.cacheReadTokens) / perMillion * (price.cacheRead ?? price.input)
        let cacheWrite =
            Double(usage.cacheWriteTokens) / perMillion * (price.cacheWrite ?? price.input)
        return input + output + cacheRead + cacheWrite
    }
}
