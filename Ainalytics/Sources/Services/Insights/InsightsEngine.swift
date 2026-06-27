import Foundation

/// Derives the Phase 10 activity insights from a `LogScanResult` — the daily
/// activity streak, peak hours, and per-provider consumption insights (model mix,
/// cache-hit ratio, input/output balance). Pure and static like `PredictionEngine`,
/// so every derivation is unit-testable without any scanner, file, or UI
/// dependency. This is the `InsightsEngine` named in ARCHITECTURE §2; the data is
/// already token-only (no message content), and nothing here fabricates a figure —
/// a thin window simply yields a zero streak / empty mix.
enum InsightsEngine {

    /// Build the full insight bundle from one scan result.
    static func insights(
        from result: LogScanResult, calendar: Calendar = .current, now: Date = .now
    ) -> ActivityInsights {
        ActivityInsights(
            streak: streak(days: result.days, calendar: calendar, now: now),
            peakHours: result.hours.sorted { $0.hour < $1.hour },
            consumption: consumption(models: result.models))
    }

    // MARK: - Streak

    /// The current run of consecutive active days ending today (or yesterday — an
    /// untouched-but-not-yet-over today does not break the streak), plus the longest
    /// active run anywhere in the scanned window. A day is "active" when it carries
    /// at least one message.
    static func streak(days: [DayActivity], calendar: Calendar, now: Date) -> ActivityStreak {
        let activeDays = Set(
            days.filter { $0.totalMessages > 0 }.map { calendar.startOfDay(for: $0.day) })
        guard !activeDays.isEmpty else { return .zero }

        // Longest run anywhere in the window.
        let ascending = activeDays.sorted()
        var longest = 1
        var run = 1
        for index in 1..<ascending.count {
            if let nextOfPrevious = calendar.date(byAdding: .day, value: 1, to: ascending[index - 1]),
                calendar.isDate(nextOfPrevious, inSameDayAs: ascending[index])
            {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
        }

        // Current run, walking back from today (or yesterday if today is still idle).
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var cursor: Date
        if activeDays.contains(today) {
            cursor = today
        } else if activeDays.contains(yesterday) {
            cursor = yesterday
        } else {
            return ActivityStreak(current: 0, longest: longest)
        }
        var current = 0
        while activeDays.contains(cursor) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return ActivityStreak(current: current, longest: longest)
    }

    // MARK: - Consumption

    /// Per-provider consumption insight: the model mix (top `topModels` by tokens,
    /// the rest folded into "Other"), the cache-hit ratio (cached input ÷ all input),
    /// and the input/output token totals. Providers are returned in `allCases` order
    /// for a stable layout.
    static func consumption(models: [ModelUsage], topModels: Int = 4) -> [ConsumptionInsight] {
        let byProvider = Dictionary(grouping: models, by: \.provider)
        return
            byProvider
            .map { provider, usages in
                let totalInput = usages.reduce(0) { $0 + $1.inputTokens }
                let totalOutput = usages.reduce(0) { $0 + $1.outputTokens }
                let totalCacheRead = usages.reduce(0) { $0 + $1.cacheReadTokens }
                let grandTotal = usages.reduce(0) { $0 + $1.totalTokens }

                // Model mix — each model's share of the provider's total tokens.
                let ranked = usages.sorted { $0.totalTokens > $1.totalTokens }
                var mix: [ModelShare] = []
                for usage in ranked.prefix(topModels) where usage.totalTokens > 0 {
                    mix.append(
                        ModelShare(
                            model: usage.model,
                            share: grandTotal > 0 ? Double(usage.totalTokens) / Double(grandTotal) : 0)
                    )
                }
                let tailTokens = ranked.dropFirst(topModels).reduce(0) { $0 + $1.totalTokens }
                if tailTokens > 0 {
                    mix.append(
                        ModelShare(
                            model: ModelShare.otherModelID,
                            share: grandTotal > 0 ? Double(tailTokens) / Double(grandTotal) : 0))
                }

                // Cache-hit ratio — fraction of input tokens that were served from cache.
                let inputBase = totalInput + totalCacheRead
                let cacheHitRatio = inputBase > 0 ? Double(totalCacheRead) / Double(inputBase) : nil

                return ConsumptionInsight(
                    provider: provider, modelMix: mix, cacheHitRatio: cacheHitRatio,
                    inputTokens: totalInput, outputTokens: totalOutput)
            }
            .sorted { lhs, rhs in
                (ProviderID.allCases.firstIndex(of: lhs.provider) ?? 0)
                    < (ProviderID.allCases.firstIndex(of: rhs.provider) ?? 0)
            }
    }
}

// MARK: - Value types

/// The full set of activity insights surfaced on the Activity page (Phase 10).
struct ActivityInsights: Sendable, Equatable {
    var streak: ActivityStreak
    /// Hour-of-day buckets (ascending), passed through from the scan.
    var peakHours: [HourActivity]
    var consumption: [ConsumptionInsight]

    static let empty = ActivityInsights(streak: .zero, peakHours: [], consumption: [])

    /// Whether any hour carries activity (the peak-hours chart has something to draw).
    var hasPeakData: Bool { peakHours.contains { $0.totalMessages > 0 } }

    /// The busiest hour-of-day under a metric, or `nil` when there is no activity.
    func peakHour(for metric: HeatmapMetric) -> Int? {
        peakHours
            .filter { $0.value(for: metric) > 0 }
            .max { $0.value(for: metric) < $1.value(for: metric) }?
            .hour
    }
}

/// A daily-activity streak: the current consecutive run and the longest run seen
/// in the scanned window.
struct ActivityStreak: Sendable, Equatable {
    var current: Int
    var longest: Int

    static let zero = ActivityStreak(current: 0, longest: 0)
}

/// Per-provider consumption insight derived from the local-log model totals.
struct ConsumptionInsight: Sendable, Equatable, Identifiable {
    let provider: ProviderID
    /// Model mix, descending by tokens, with a trailing "Other" bucket where the
    /// long tail was folded together.
    var modelMix: [ModelShare]
    /// Cached-input ÷ total-input, 0…1. `nil` when the provider logged no input.
    var cacheHitRatio: Double?
    var inputTokens: Int
    var outputTokens: Int

    var id: ProviderID { provider }

    /// Whether there is anything worth showing for this provider.
    var hasData: Bool { inputTokens + outputTokens > 0 || !modelMix.isEmpty }
}

/// One model's share of a provider's total token consumption.
struct ModelShare: Sendable, Equatable, Identifiable {
    /// Sentinel model id for the folded long-tail bucket; the UI shows a localized
    /// "Other" instead of this raw value.
    static let otherModelID = "__other__"

    let model: String
    /// Fraction of the provider's total tokens, 0…1.
    let share: Double

    var id: String { model }
    var isOther: Bool { model == ModelShare.otherModelID }
}
