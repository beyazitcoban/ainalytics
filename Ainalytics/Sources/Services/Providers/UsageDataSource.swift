import Foundation

/// The AI providers Ainalytics tracks in v1. String-backed (`Codable`) so the
/// raw value can persist in SwiftData and `UserDefaults`.
enum ProviderID: String, CaseIterable, Codable, Sendable {
    case claude
    case codex

    /// Human-facing name. Not localized here — the UI localizes via String Catalog;
    /// this is the stable internal label.
    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "ChatGPT"
        }
    }
}

/// The connection state of a single provider. Drives graceful degradation —
/// one provider failing never blocks the others (ARCHITECTURE §10).
enum ProviderConnection: Equatable, Sendable {
    case unknown  // not checked yet
    case connected  // credential present and locatable
    case notInstalled  // no credential file / keychain item found
    case tokenExpired  // credential present but expired → user re-logs in their CLI
    case endpointError(String)  // reserved for Phase 2 (fetch failures)

    var isConnected: Bool { self == .connected }
}

/// A single rolling usage window returned by a provider.
struct UsageWindow: Identifiable, Sendable {
    let id: String  // provider window key, e.g. "five_hour", "seven_day_sonnet"
    let kind: UsageWindowKind
    /// Provider-specific display name for windows beyond the common Session/Weekly
    /// (e.g. "Sonnet", "Opus", a model name). nil → the UI uses the localized
    /// `kind` label. Proper nouns / model names are shown verbatim (not localized).
    let title: String?
    let used: Double
    let limit: Double
    let resetsAt: Date?
}

/// The kind of rolling window a provider reports. Avoids stringly-typed data
/// (code-principles §4); the SwiftData layer stores the `rawValue`.
enum UsageWindowKind: String, Codable, Sendable {
    case fiveHour
    case weekly
    case monthly
    case unknown
}

enum UsageDataSourceError: Error {
    /// No credential file or keychain item present for this provider.
    case notInstalled
    /// Credential present but its contents could not be parsed.
    case credentialUnreadable
    /// Credential present but expired, or the endpoint returned 401/403.
    /// Read-only policy: the app never refreshes — the user re-logs in their CLI.
    case tokenExpired
    /// Network, HTTP (non-2xx, non-401/403), or response-decoding failure.
    case endpoint(String)
}

extension UsageWindow {
    /// Percent of this window already consumed (0–100). All three providers are
    /// normalized onto a percent scale (`limit` is stored as 100), so this ratio
    /// is uniform regardless of how the provider reported its raw numbers.
    var percentUsed: Double { limit > 0 ? min(100, (used / limit) * 100) : 0 }

    /// Percent of this window still available (0–100).
    var percentRemaining: Double { max(0, 100 - percentUsed) }
}

/// The result of one usage fetch: the parsed windows plus the raw endpoint body.
struct UsageReport: Sendable {
    let windows: [UsageWindow]
    /// The unparsed endpoint response (pretty JSON), surfaced in the Debug
    /// raw-data view so displayed numbers can be verified against source
    /// (Critical Pass #4). In-memory only — never logged, never persisted.
    /// Holds usage numbers, not the token.
    let rawResponse: String?
}

/// A read-only source of usage data for one provider.
///
/// Exactly two concrete conformances (Claude / Codex) — deliberately
/// NOT a generic plugin framework (Critical Pass #2).
protocol UsageDataSource: Sendable {
    var id: ProviderID { get }

    /// Detect whether the provider's CLI credential is present and usable.
    /// Read-only — never reads the token value, never logs it, never writes it.
    func detectConnection() async -> ProviderConnection

    /// Fetch the current usage windows from the provider's private endpoint.
    /// Throws `UsageDataSourceError` on any degraded outcome so the poller can
    /// map it to a `ProviderConnection` (graceful degradation, ARCHITECTURE §10).
    func fetchUsage() async throws -> UsageReport
}
