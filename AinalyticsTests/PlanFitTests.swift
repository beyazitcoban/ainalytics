import Foundation
import Testing

@testable import Ainalytics

/// Unit tests for `PlanFit` — the right-sizing projection (peak × capacity ratio),
/// verdict thresholds, plan filtering, and the recommendation. Pure, no UI.
struct PlanFitTests {

    @Test func verdictThresholds() {
        #expect(PlanFit.verdict(forProjectedPeak: 50) == .fits)
        #expect(PlanFit.verdict(forProjectedPeak: 85) == .fits)
        #expect(PlanFit.verdict(forProjectedPeak: 90) == .tight)
        #expect(PlanFit.verdict(forProjectedPeak: 100) == .tight)
        #expect(PlanFit.verdict(forProjectedPeak: 101) == .over)
        #expect(PlanFit.verdict(forProjectedPeak: 248) == .over)
    }

    @Test func projectionScalesByCapacityRatio() {
        let max20 = PlanPriceCatalog.plan(for: .claude, key: "max_20x")!
        let max5 = PlanPriceCatalog.plan(for: .claude, key: "max_5x")!
        // 15% of 20x → 60% of 5x (×4 the relative fill on a quarter-size cap).
        #expect(PlanFit.projectedPeak(currentPeak: 15, current: max20, candidate: max5) == 60)
        // Same plan → unchanged.
        #expect(PlanFit.projectedPeak(currentPeak: 62, current: max20, candidate: max20) == 62)
    }

    @Test func projectionNilForUnknownCapacity() {
        let plus = PlanPriceCatalog.plan(for: .codex, key: "plus")!
        let go = PlanPriceCatalog.plan(for: .codex, key: "go")!  // relativeCapacity nil
        #expect(PlanFit.projectedPeak(currentPeak: 50, current: plus, candidate: go) == nil)
        #expect(PlanFit.projectedPeak(currentPeak: 50, current: go, candidate: plus) == nil)
    }

    @Test func resultsExcludeUnknownCapacityAndAreSorted() {
        let results = PlanFit.results(provider: .codex, currentKey: "pro_20x", currentPeak: 40)
        // Go (nil capacity) is excluded; the rest ascend by capacity.
        #expect(!results.contains { $0.plan.key == "go" })
        #expect(results.map(\.plan.key) == ["plus", "pro_5x", "pro_20x"])
        #expect(results.first { $0.isCurrent }?.plan.key == "pro_20x")
    }

    @Test func resultsEmptyForUnknownCurrentPlan() {
        // Current plan has no known capacity (Go) or doesn't exist → no comparison.
        #expect(PlanFit.results(provider: .codex, currentKey: "go", currentPeak: 40).isEmpty)
        #expect(PlanFit.results(provider: .claude, currentKey: "nonsense", currentPeak: 40).isEmpty)
    }

    @Test func recommendsDownsizeWhenPeakIsLow() {
        // 15% on Max 20x → Max 5x projects to 60% (fits), Pro to 300% (over).
        let rec = PlanFit.recommendation(provider: .claude, currentKey: "max_20x", currentPeak: 15)
        #expect(rec?.key == "max_5x")
    }

    @Test func recommendsCurrentWhenPeakIsHigh() {
        // 62% on Max 20x → Max 5x would be 248% (over) → stay on Max 20x.
        let rec = PlanFit.recommendation(provider: .claude, currentKey: "max_20x", currentPeak: 62)
        #expect(rec?.key == "max_20x")
    }
}
