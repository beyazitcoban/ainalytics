import Foundation
import Testing

@testable import Ainalytics

/// Pure-function tests for the burn-rate `PredictionEngine`. Deterministic — fixed
/// dates, no `Date.now` — so each case always yields the same forecast (Rule #4).
struct PredictionEngineTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3_600) }

    @Test func fewerThanTwoPointsIsInsufficient() {
        #expect(PredictionEngine.forecast(points: [], resetsAt: nil) == .insufficientData)
        #expect(
            PredictionEngine.forecast(
                points: [BurnPoint(date: t0, percent: 40)], resetsAt: nil) == .insufficientData)
    }

    @Test func flatSeriesIsOnTrack() {
        let points = [BurnPoint(date: at(0), percent: 40), BurnPoint(date: at(2), percent: 40)]
        #expect(PredictionEngine.forecast(points: points, resetsAt: at(100)) == .onTrack)
    }

    @Test func risingBeforeResetWarns() {
        // 50% → 60% over 1h = 10%/h; 40% remaining → +4h → exhaustion at t0+5h.
        let points = [BurnPoint(date: at(0), percent: 50), BurnPoint(date: at(1), percent: 60)]
        let forecast = PredictionEngine.forecast(points: points, resetsAt: at(10))
        guard case let .willRunOut(date, beforeReset) = forecast else {
            Issue.record("expected willRunOut, got \(forecast)")
            return
        }
        #expect(beforeReset)
        #expect(abs(date.timeIntervalSince(at(5))) < 1)
    }

    @Test func resetBeforeExhaustionIsSafe() {
        // Same 10%/h rate, but the window resets at t0+2h — before the t0+5h run-out.
        let points = [BurnPoint(date: at(0), percent: 50), BurnPoint(date: at(1), percent: 60)]
        let forecast = PredictionEngine.forecast(points: points, resetsAt: at(2))
        guard case let .willRunOut(_, beforeReset) = forecast else {
            Issue.record("expected willRunOut, got \(forecast)")
            return
        }
        #expect(!beforeReset)
    }

    @Test func resetDropStartsNewCycle() {
        // A drop (95→10) marks a reset; only the post-reset cycle (10→20) is used,
        // so the old high values do not poison the rate (and it is not "already full").
        let points = [
            BurnPoint(date: at(0), percent: 90),
            BurnPoint(date: at(1), percent: 95),
            BurnPoint(date: at(2), percent: 10),
            BurnPoint(date: at(3), percent: 20),
        ]
        let forecast = PredictionEngine.forecast(points: points, resetsAt: at(50))
        guard case let .willRunOut(date, _) = forecast else {
            Issue.record("expected willRunOut, got \(forecast)")
            return
        }
        // 10→20 over 1h = 10%/h; 80% remaining → +8h from t0+3h → t0+11h.
        #expect(abs(date.timeIntervalSince(at(11))) < 1)
    }

    @Test func mostUrgentPicksEarliestBeforeReset() {
        let early = BurnRateForecast.willRunOut(at: at(3), beforeReset: true)
        let late = BurnRateForecast.willRunOut(at: at(30), beforeReset: true)
        #expect(PredictionEngine.mostUrgent([.onTrack, late, early]) == early)
    }

    @Test func mostUrgentFallsBackToOnTrack() {
        #expect(PredictionEngine.mostUrgent([.onTrack, .insufficientData]) == .onTrack)
        #expect(PredictionEngine.mostUrgent([.insufficientData]) == .insufficientData)
    }
}
