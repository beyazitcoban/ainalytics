import Foundation

/// One observation of a window's consumption at a point in time: percent used
/// (0...100) at `date`. The burn-rate engine works on these plain points so it
/// stays pure and unit-testable — the view maps `UsageSnapshot`s into them.
struct BurnPoint: Equatable, Sendable {
    let date: Date
    let percent: Double
}

/// The burn-rate forecast for one window.
enum BurnRateForecast: Equatable, Sendable {
    /// Fewer than two readings in the current cycle — nothing to project yet.
    case insufficientData
    /// Flat or declining within the cycle — not on pace to run out.
    case onTrack
    /// Projected to reach 100% at `date`. `beforeReset` is true when that lands
    /// before the window resets (the case worth warning about); false means the
    /// window resets first, so the user would not actually run out.
    case willRunOut(at: Date, beforeReset: Bool)
}

/// Predicts when a usage window will be exhausted from its recent history.
///
/// Pure and deterministic (no `Date.now`, no I/O) so it is fully unit-testable:
/// given the same points + reset it always returns the same forecast. It fits a
/// simple linear rate over the *current* cycle (a window reset shows up as a drop
/// in percent used, which starts a fresh cycle) and extrapolates to 100%.
enum PredictionEngine {

    /// A drop larger than this (percentage points) between consecutive readings is
    /// treated as a window reset — the boundary that starts a new cycle.
    private static let resetDropThreshold: Double = 5
    /// The cycle must have risen at least this much to count as a real burn (else
    /// it is flat/noise → `onTrack`).
    private static let minimumRise: Double = 0.5

    /// Forecast exhaustion for one window from its readings (any order) and the
    /// current window's reset time (the latest reading's `resetsAt`).
    static func forecast(points rawPoints: [BurnPoint], resetsAt: Date?) -> BurnRateForecast {
        let cycle = currentCycle(of: rawPoints.sorted { $0.date < $1.date })
        guard cycle.count >= 2, let first = cycle.first, let last = cycle.last else {
            return .insufficientData
        }

        let elapsed = last.date.timeIntervalSince(first.date)
        let rise = last.percent - first.percent
        guard elapsed > 0, rise > minimumRise else { return .onTrack }

        // Already at the limit → out now.
        let remaining = 100 - last.percent
        guard remaining > 0 else {
            return .willRunOut(at: last.date, beforeReset: beforeReset(last.date, resetsAt))
        }

        let ratePerSecond = rise / elapsed
        let secondsToFull = remaining / ratePerSecond
        let exhaustion = last.date.addingTimeInterval(secondsToFull)
        return .willRunOut(at: exhaustion, beforeReset: beforeReset(exhaustion, resetsAt))
    }

    /// Picks the most urgent forecast across a provider's windows: a
    /// `willRunOut(beforeReset: true)` with the earliest date wins; otherwise the
    /// first `onTrack`/safe case; `insufficientData` only when nothing else exists.
    static func mostUrgent(_ forecasts: [BurnRateForecast]) -> BurnRateForecast {
        let urgent =
            forecasts
            .compactMap { forecast -> (Date, BurnRateForecast)? in
                if case let .willRunOut(date, true) = forecast { return (date, forecast) }
                return nil
            }
            .min { $0.0 < $1.0 }
        if let urgent { return urgent.1 }
        if forecasts.contains(where: { if case .willRunOut = $0 { return true } else { return false } }) {
            return forecasts.first { if case .willRunOut = $0 { return true } else { return false } }!
        }
        if forecasts.contains(.onTrack) { return .onTrack }
        return .insufficientData
    }

    // MARK: - Internals

    /// The points belonging to the current cycle — everything after the last reset
    /// (a drop in percent used larger than `resetDropThreshold`). Input must be
    /// ascending by date.
    private static func currentCycle(of points: [BurnPoint]) -> [BurnPoint] {
        guard !points.isEmpty else { return [] }
        var start = 0
        for i in 1..<points.count where points[i].percent + resetDropThreshold < points[i - 1].percent {
            start = i
        }
        return Array(points[start...])
    }

    private static func beforeReset(_ exhaustion: Date, _ resetsAt: Date?) -> Bool {
        guard let resetsAt else { return true }  // no known reset → treat as a real run-out
        return exhaustion < resetsAt
    }
}
