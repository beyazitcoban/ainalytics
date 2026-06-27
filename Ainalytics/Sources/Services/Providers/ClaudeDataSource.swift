import Foundation

/// Claude (Anthropic) usage data source.
///
/// Credential lives either in `~/.claude/.credentials.json` OR in the macOS
/// Keychain item `"Claude Code-credentials"` (Claude Code writes one or the other;
/// on many machines only the Keychain item exists). File first, Keychain fallback,
/// both read-only.
///
/// Usage endpoint contract (verified against steipete/CodexBar):
/// `GET api.anthropic.com/api/oauth/usage` with `Authorization: Bearer`,
/// `anthropic-beta: oauth-2025-04-20`, and the `claude-code/<ver>` User-Agent.
/// The response is a map of window → `{ utilization, resets_at }`, where
/// `utilization` is the percent already used and `resets_at` is ISO-8601.
struct ClaudeDataSource: UsageDataSource {
    let id: ProviderID = .claude

    private static let credentialFile = "~/.claude/.credentials.json"
    private static let keychainService = "Claude Code-credentials"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// CLI-impersonation User-Agent. We do not know the user's installed CLI version,
    /// so a recent stable value is used (the endpoint gates on the bearer token, not
    /// the exact version). Patchable in one place if Anthropic tightens this.
    private static let userAgent = "claude-code/2.1.0"

    func detectConnection() async -> ProviderConnection {
        if TokenLocator.fileExists(at: Self.credentialFile) { return .connected }
        if TokenLocator.keychainItemExists(service: Self.keychainService) { return .connected }
        return .notInstalled
    }

    func fetchUsage() async throws -> UsageReport {
        let credentials = try readCredentials()

        // Expiry check before spending a network call (read-only: we never refresh).
        if let expiresAtMS = credentials.expiresAtMS,
            Date(timeIntervalSince1970: expiresAtMS / 1000) < .now
        {
            throw UsageDataSourceError.tokenExpired
        }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data = try await UsageHTTP.data(for: request)
        let raw = UsageHTTP.prettyJSON(from: data)
        // Parse defensively: read only the window keys we surface, tolerating any
        // sibling top-level keys (e.g. extra_usage, plan) of other shapes. A 2xx
        // body we cannot map yields an empty list (never a throw) — AppState then
        // surfaces the raw body in the Debug view (Critical Pass #4).
        return UsageReport(windows: Self.parseWindows(from: data), rawResponse: raw)
    }

    /// Extracts every usage window from the body — the common Session + Weekly
    /// plus model-specific ones (Sonnet, Opus) and any others Anthropic returns.
    /// Uses `JSONSerialization` so a non-object sibling key (which would break a
    /// `[String: Decodable]` decode) cannot fail the whole parse; non-window keys
    /// (e.g. `extra_usage`, which has no `utilization`) are simply skipped.
    private static func parseWindows(from data: Data) -> [UsageWindow] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var windows: [UsageWindow] = []
        var seen = Set<String>()

        // Known windows first, in display order, with friendly labels.
        for entry in knownWindowLabels {
            if let window = Self.makeWindow(
                key: entry.key, kind: entry.kind, title: entry.title, from: root)
            {
                windows.append(window)
                seen.insert(entry.key)
            }
        }
        // Any remaining utilization-bearing window — surfaced (humanized) so nothing
        // is hidden ("hepsi detaylı görünmeli"); explicit labels can be added later.
        for key in root.keys.sorted() where !seen.contains(key) {
            if let window = Self.makeWindow(
                key: key, kind: .unknown, title: Self.humanize(key), from: root)
            {
                windows.append(window)
            }
        }
        return windows
    }

    /// Window key → (kind, friendly title). Session/Weekly use the localized `kind`
    /// label (title nil); model windows show their proper noun verbatim.
    private static let knownWindowLabels: [(key: String, kind: UsageWindowKind, title: String?)] = [
        ("five_hour", .fiveHour, nil),
        ("seven_day", .weekly, nil),
        ("seven_day_sonnet", .unknown, "Sonnet"),
        ("seven_day_opus", .unknown, "Opus"),
    ]

    private static func makeWindow(
        key: String, kind: UsageWindowKind, title: String?, from root: [String: Any]
    ) -> UsageWindow? {
        guard let window = root[key] as? [String: Any],
            let utilization = (window["utilization"] as? NSNumber)?.doubleValue
        else { return nil }
        return UsageWindow(
            id: key,
            kind: kind,
            title: title,
            used: utilization,
            limit: 100,
            resetsAt: UsageHTTP.parseISODate(window["resets_at"] as? String))
    }

    /// "seven_day_oauth_apps" → "Seven Day Oauth Apps" — a readable fallback until a
    /// window key gets an explicit label above.
    private static func humanize(_ key: String) -> String {
        key.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    private func readCredentials() throws -> ClaudeCredentials.OAuth {
        let data: Data
        if let fileData = TokenLocator.readFileData(at: Self.credentialFile) {
            data = fileData
        } else if TokenLocator.keychainItemExists(service: Self.keychainService) {
            // The item is present — a nil read means keychain access wasn't granted
            // for this build's signature, NOT that Claude isn't installed. Surface it
            // as unreadable so the UI doesn't misreport "not installed".
            guard let keychainData = TokenLocator.readKeychainData(service: Self.keychainService)
            else {
                throw UsageDataSourceError.credentialUnreadable
            }
            data = keychainData
        } else {
            throw UsageDataSourceError.notInstalled
        }
        guard let credentials = try? JSONDecoder().decode(ClaudeCredentials.self, from: data) else {
            throw UsageDataSourceError.credentialUnreadable
        }
        return credentials.claudeAiOauth
    }
}

// MARK: - DTOs

/// Credential JSON shape: `{ "claudeAiOauth": { "accessToken", "expiresAt", ... } }`.
private struct ClaudeCredentials: Decodable {
    let claudeAiOauth: OAuth

    struct OAuth: Decodable {
        let accessToken: String
        /// Unix epoch in milliseconds (Claude's encoding); optional → treated as no expiry.
        let expiresAtMS: Double?

        enum CodingKeys: String, CodingKey {
            case accessToken
            case expiresAtMS = "expiresAt"
        }
    }
}
