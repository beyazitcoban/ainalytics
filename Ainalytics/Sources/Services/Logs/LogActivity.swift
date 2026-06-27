import Foundation

/// Per-day activity rolled up from the local CLI session logs. Holds derived
/// counts only — token totals and message counts — never message content and
/// never any credential (the scanner extracts a handful of numbers per line and
/// discards the rest). Both metrics are kept so the heatmap can switch between
/// "tokens used" and "messages" intensity.
struct DayActivity: Sendable, Equatable {
    /// Start-of-day (local calendar) for the day this bucket covers.
    let day: Date
    /// Total tokens (input + output + cache) per provider on this day.
    var tokensByProvider: [ProviderID: Int]
    /// Assistant-response / token-event count per provider on this day.
    var messagesByProvider: [ProviderID: Int]

    var totalTokens: Int { tokensByProvider.values.reduce(0, +) }
    var totalMessages: Int { messagesByProvider.values.reduce(0, +) }

    /// The activity value for the heatmap under the selected metric.
    func value(for metric: HeatmapMetric) -> Int {
        switch metric {
        case .tokens: totalTokens
        case .messages: totalMessages
        }
    }
}

/// Which quantity the activity heatmap colours each day by. Both are derived
/// from the same scan, so switching is instant (no re-scan).
enum HeatmapMetric: String, CaseIterable, Sendable {
    case tokens
    case messages
}

/// Activity within one hour-of-day bucket (0–23, local calendar), rolled up across
/// the whole scanned window. Mirrors `DayActivity` (provider-attributed token and
/// message counts) so the peak-hours chart can reuse the same metric toggle and
/// per-provider accent colours. Powers the Phase 10 "peak hours" insight.
struct HourActivity: Sendable, Equatable, Identifiable {
    /// Hour of day, 0–23 (local calendar).
    let hour: Int
    /// Total tokens per provider attributed to this hour-of-day.
    var tokensByProvider: [ProviderID: Int]
    /// Message / token-event count per provider attributed to this hour-of-day.
    var messagesByProvider: [ProviderID: Int]

    var id: Int { hour }
    var totalTokens: Int { tokensByProvider.values.reduce(0, +) }
    var totalMessages: Int { messagesByProvider.values.reduce(0, +) }

    /// The activity value for this hour under the selected metric.
    func value(for metric: HeatmapMetric) -> Int {
        switch metric {
        case .tokens: totalTokens
        case .messages: totalMessages
        }
    }
}

/// Cumulative token usage for one model on one provider across the scanned
/// window. Feeds the cost engine and the token-based "most used model" stat
/// (which replaces Phase 4's live-window proxy).
struct ModelUsage: Sendable, Identifiable, Equatable {
    let provider: ProviderID
    let model: String
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int

    var id: String { "\(provider.rawValue)/\(model)" }
    var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens }
}

/// The full result of one log scan: per-day activity (the heatmap) plus per-model
/// token usage (cost + most-used model). A value type, computed off the main actor.
struct LogScanResult: Sendable, Equatable {
    /// One entry per day that had activity, ascending by date. Days with no
    /// activity are omitted — the heatmap renders the gaps at the empty level.
    var days: [DayActivity]
    /// Per-model token usage across the window, for every provider with data.
    var models: [ModelUsage]
    /// Per-hour-of-day activity (0–23) across the window, for the peak-hours
    /// insight (Phase 10). Only hours with activity are present.
    var hours: [HourActivity]

    static let empty = LogScanResult(days: [], models: [], hours: [])

    /// The model with the most total tokens for a provider — the real,
    /// token-based "most used model". `nil` when the provider has no log data.
    func mostUsedModel(for provider: ProviderID) -> ModelUsage? {
        models.filter { $0.provider == provider }.max { $0.totalTokens < $1.totalTokens }
    }
}
