import Foundation
import Testing

@testable import Ainalytics

/// Unit tests for `PlanPriceCatalog` — the catalog lookup and the effective-price
/// resolution (`manual ?? catalog`) that drives the ROI view. Pure, no UI.
struct PlanPriceCatalogTests {

    @Test func cataloguedPlansExistForBothProviders() {
        #expect(!PlanPriceCatalog.plans(for: .claude).isEmpty)
        #expect(!PlanPriceCatalog.plans(for: .codex).isEmpty)
    }

    @Test func priceLookupReturnsCataloguedValue() {
        #expect(PlanPriceCatalog.price(for: .claude, key: "pro") == 20)
        #expect(PlanPriceCatalog.price(for: .claude, key: "max_5x") == 100)
        #expect(PlanPriceCatalog.price(for: .claude, key: "max_20x") == 200)
        #expect(PlanPriceCatalog.price(for: .codex, key: "go") == 6)
        #expect(PlanPriceCatalog.price(for: .codex, key: "plus") == 20)
        #expect(PlanPriceCatalog.price(for: .codex, key: "pro_5x") == 120)
        #expect(PlanPriceCatalog.price(for: .codex, key: "pro_20x") == 200)
    }

    @Test func unknownOrNilKeyResolvesToNil() {
        #expect(PlanPriceCatalog.price(for: .claude, key: "nonsense") == nil)
        #expect(PlanPriceCatalog.price(for: .claude, key: nil) == nil)
        #expect(PlanPriceCatalog.plan(for: .codex, key: "stale_key") == nil)
    }

    @Test func manualPriceOverridesCatalog() {
        // A typed price wins even when a plan is selected.
        let p = PlanPriceCatalog.effectiveMonthlyPrice(
            manual: 17, provider: .claude, selectedPlanKey: "pro")
        #expect(p == 17)
    }

    @Test func catalogUsedWhenNoManual() {
        let p = PlanPriceCatalog.effectiveMonthlyPrice(
            manual: nil, provider: .claude, selectedPlanKey: "max_5x")
        #expect(p == 100)
    }

    @Test func nonPositiveManualFallsBackToCatalog() {
        // Zero / cleared field is not a real override → use the plan price.
        let p = PlanPriceCatalog.effectiveMonthlyPrice(
            manual: 0, provider: .codex, selectedPlanKey: "plus")
        #expect(p == 20)
    }

    @Test func noManualAndNoPlanIsNil() {
        // Neither set → ROI shows its prompt (nil), never a misleading 0.
        let p = PlanPriceCatalog.effectiveMonthlyPrice(
            manual: nil, provider: .claude, selectedPlanKey: nil)
        #expect(p == nil)
    }

    @Test func unknownSelectedPlanWithoutManualIsNil() {
        // A stale stored key (after a catalog change) degrades gracefully.
        let p = PlanPriceCatalog.effectiveMonthlyPrice(
            manual: nil, provider: .codex, selectedPlanKey: "stale_key")
        #expect(p == nil)
    }
}
