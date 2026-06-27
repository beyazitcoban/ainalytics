import Foundation

/// Per-provider runtime snapshot for the UI: connection state, the latest usage
/// windows, when it was last fetched, an optional error message, and the raw
/// endpoint body (for the Debug verifiability view). A value type — `AppState`
/// holds one per provider and replaces it wholesale on each refresh.
struct ProviderRuntime: Sendable {
    var connection: ProviderConnection
    var windows: [UsageWindow]
    var lastFetched: Date?
    var errorMessage: String?
    /// Raw endpoint JSON for the Debug raw-data view. In-memory only — never
    /// logged, never persisted. Holds usage numbers, not the token.
    var rawResponse: String?

    static let unknown = ProviderRuntime(
        connection: .unknown, windows: [], lastFetched: nil, errorMessage: nil, rawResponse: nil)

    /// The window to headline in the menu bar — the one closest to its limit
    /// (highest percent used), since that is the binding constraint.
    var primaryWindow: UsageWindow? {
        windows.max(by: { $0.percentUsed < $1.percentUsed })
    }

    /// The window whose reset stands in for the "renewal" date on the dashboard.
    /// The usage endpoints do not expose true billing/subscription dates, so the
    /// longest rolling cycle is the honest best-available proxy: monthly > weekly
    /// > five-hour. Ties break on the latest reset. `nil` when no window resets.
    var subscriptionWindow: UsageWindow? {
        windows.max { lhs, rhs in
            if lhs.kind.cycleRank != rhs.kind.cycleRank {
                return lhs.kind.cycleRank < rhs.kind.cycleRank
            }
            return (lhs.resetsAt ?? .distantPast) < (rhs.resetsAt ?? .distantPast)
        }
    }

    /// The model-named window closest to its limit — the dashboard's "most active
    /// model" stat. A live-data proxy; token-based "most used" arrives with the
    /// Phase 5 log engine. `nil` when the provider reports no model-named windows.
    var mostActiveModelWindow: UsageWindow? {
        windows.filter { $0.title != nil }.max { $0.percentUsed < $1.percentUsed }
    }
}

extension UsageWindowKind {
    /// Ordering for "which window is the longest cycle" — higher is longer. Used by
    /// `ProviderRuntime.subscriptionWindow` to pick the renewal-date window.
    fileprivate var cycleRank: Int {
        switch self {
        case .monthly: 3
        case .weekly: 2
        case .fiveHour: 1
        case .unknown: 0
        }
    }
}

extension ProviderConnection {
    /// Stable string for SwiftData persistence (`ProviderState.statusRaw`).
    /// Kept separate from any UI text so the persisted value never shifts with
    /// localization or display wording.
    var persistedRaw: String {
        switch self {
        case .unknown: "unknown"
        case .connected: "connected"
        case .notInstalled: "notInstalled"
        case .tokenExpired: "tokenExpired"
        case .endpointError: "endpointError"
        }
    }
}
