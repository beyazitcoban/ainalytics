import Foundation

/// One selectable subscription plan: a stable `key`, a `displayName` (a proper
/// noun shown verbatim — never localized), the monthly USD price, and the usage
/// capacity relative to the provider's baseline paid tier.
struct PlanOption: Identifiable, Sendable, Equatable {
    let key: String
    let displayName: String
    let monthlyUSD: Double
    /// Usage capacity relative to the provider's baseline paid tier (Pro/Plus = 1).
    /// The 5x / 20x tiers are 5 / 20. `nil` when the provider publishes no clean
    /// multiple (ChatGPT Go) — such a plan is excluded from right-sizing rather than
    /// guessed (Rule #4). Drives `PlanFit`.
    let relativeCapacity: Double?
    var id: String { key }
}

/// Bundled, **dated and overridable** catalog of consumer subscription plans and
/// their monthly USD prices, feeding the ROI ("is it worth it") comparison.
///
/// The provider usage endpoints do not reliably expose the plan — Claude's carries
/// no plan field at all (verified 2026-06-27), and ChatGPT's `plan_type` covers only
/// some tiers — so the user **picks** their plan in Settings; a typed price still
/// overrides the catalog value. Distinct from the per-token `ModelPriceCatalog`.
///
/// Prices verified 2026-06-27, Personal plans billed monthly:
/// - Claude  — claude.com/pricing (Pro $20, Max 5x $100, Max 20x $200)
/// - ChatGPT — OpenAI in-app plan UI (Go $6, Plus $20, Pro 5x $120, Pro 20x $200)
/// Static convenience; providers change prices, so staleness is expected → the
/// manual price field always wins, and these are trivial to update in one place.
enum PlanPriceCatalog {
    /// Selectable plans per provider, in display order. The user picks one in Settings.
    static let plans: [ProviderID: [PlanOption]] = [
        .claude: [
            PlanOption(key: "pro", displayName: "Pro", monthlyUSD: 20, relativeCapacity: 1),
            PlanOption(key: "max_5x", displayName: "Max 5x", monthlyUSD: 100, relativeCapacity: 5),
            PlanOption(key: "max_20x", displayName: "Max 20x", monthlyUSD: 200, relativeCapacity: 20),
        ],
        .codex: [
            PlanOption(key: "go", displayName: "Go", monthlyUSD: 6, relativeCapacity: nil),
            PlanOption(key: "plus", displayName: "Plus", monthlyUSD: 20, relativeCapacity: 1),
            PlanOption(key: "pro_5x", displayName: "Pro (5x)", monthlyUSD: 120, relativeCapacity: 5),
            PlanOption(key: "pro_20x", displayName: "Pro (20x)", monthlyUSD: 200, relativeCapacity: 20),
        ],
    ]

    /// The plans offered for a provider, in display order (empty if none catalogued).
    static func plans(for provider: ProviderID) -> [PlanOption] {
        plans[provider] ?? []
    }

    /// The catalogued plan for a (provider, key), or `nil` for an unknown key — e.g.
    /// a stale stored selection after a catalog change (graceful, never a crash).
    static func plan(for provider: ProviderID, key: String?) -> PlanOption? {
        guard let key else { return nil }
        return plans(for: provider).first { $0.key == key }
    }

    /// The catalog price for a selected plan, or `nil` if none/unknown.
    static func price(for provider: ProviderID, key: String?) -> Double? {
        plan(for: provider, key: key)?.monthlyUSD
    }

    /// The price the ROI view should use: a positive manual override wins; otherwise
    /// the selected plan's catalog price; otherwise `nil` (ROI shows its prompt).
    static func effectiveMonthlyPrice(
        manual: Double?, provider: ProviderID, selectedPlanKey: String?
    ) -> Double? {
        if let manual, manual > 0 { return manual }
        return price(for: provider, key: selectedPlanKey)
    }
}
