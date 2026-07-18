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

    /// Extracts the usage windows from the body (Phase 17).
    ///
    /// **Primary — the `limits` array.** Anthropic now returns model/surface-specific
    /// weekly limits (Fable/Sonnet/Opus, Cowork) in a `limits` array alongside the
    /// plan-wide Session/Weekly, each element carrying a `scope` + `is_active`. When
    /// present, this is authoritative and is parsed whole.
    ///
    /// **Fallback — the legacy top-level keys** (`five_hour`/`seven_day`/…). When the
    /// `limits` array is absent (or carried nothing usable), the old top-level windows
    /// are read, so an undocumented-endpoint shape change degrades to Session/Weekly
    /// instead of breaking (extends the ARCHITECTURE §10 graceful-degradation rule).
    ///
    /// `JSONSerialization` (not a typed decode) so a non-object sibling key can't fail
    /// the whole parse. Internal (not `private`) so the mapping is unit-testable.
    static func parseWindows(from data: Data) -> [UsageWindow] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        // Primary: the `limits` array (plan-wide + model/surface-scoped windows).
        if let limits = root["limits"] as? [[String: Any]], !limits.isEmpty {
            let parsed = parseLimits(limits)
            if !parsed.isEmpty {
                if parsed.contains(where: \.isGeneral) { return parsed }
                // Defensive: the array carried only scoped windows — backfill the
                // first-class Session/Weekly from the legacy keys so the headline
                // (menu bar / widget / forecast) never vanishes.
                return parseLegacyWindows(from: root).filter(\.isGeneral) + parsed
            }
        }
        // Fallback: no usable `limits` array → the legacy top-level keys only.
        return parseLegacyWindows(from: root)
    }

    // MARK: - `limits` array (primary)

    /// Map each `limits` element to a `UsageWindow`. An element missing a percent is
    /// skipped (a single malformed element never fails the whole parse).
    private static func parseLimits(_ limits: [[String: Any]]) -> [UsageWindow] {
        limits.compactMap(makeLimitWindow)
    }

    /// One `limits` element:
    /// `{ group: "session"|"weekly", utilization|percent, resets_at, is_active,
    ///    scope: { model: { display_name }, surface } }`.
    private static func makeLimitWindow(from element: [String: Any]) -> UsageWindow? {
        guard
            let percent = (element["utilization"] as? NSNumber)?.doubleValue
                ?? (element["percent"] as? NSNumber)?.doubleValue
        else { return nil }

        let group = (element["group"] as? String)?.lowercased()
        let kind: UsageWindowKind =
            switch group {
            case "session": .fiveHour
            case "weekly": .weekly
            default: .unknown
            }
        let scope = parseScope(element["scope"])
        let isActive = (element["is_active"] as? Bool) ?? true
        let resetsAt = UsageHTTP.parseISODate(element["resets_at"] as? String)

        let title: String?
        let id: String
        switch scope {
        case .general:
            // Reuse the legacy ids so notification "armed" memory + snapshot history
            // carry across the transition from top-level keys to the `limits` array.
            title = nil
            switch kind {
            case .fiveHour: id = "five_hour"
            case .weekly: id = "seven_day"
            default: id = "limit_\(group ?? "unknown")"
            }
        case .model(let name):
            title = name
            id = "seven_day_model_\(name)"
        case .surface(let name):
            title = name
            id = "seven_day_surface_\(name)"
        }

        return UsageWindow(
            id: id, kind: kind, title: title, used: percent, limit: 100,
            resetsAt: resetsAt, scope: scope, isActive: isActive)
    }

    /// Read a `limits[].scope` object into a `UsageWindowScope`. Model scope wins over
    /// surface when both are present (the more specific label). A scope value may be a
    /// nested object (`{ display_name }`) or a bare string. Absent / unrecognized →
    /// `.general`.
    private static func parseScope(_ raw: Any?) -> UsageWindowScope {
        guard let scope = raw as? [String: Any] else { return .general }
        if let name = displayName(from: scope["model"]) { return .model(name) }
        if let name = displayName(from: scope["surface"]) { return .surface(name) }
        return .general
    }

    /// A scope qualifier's display name from either a `{ display_name | name }` object
    /// or a bare string (humanized). `nil` when absent / empty.
    private static func displayName(from raw: Any?) -> String? {
        if let object = raw as? [String: Any] {
            let name = (object["display_name"] as? String) ?? (object["name"] as? String)
            return name.flatMap { $0.isEmpty ? nil : $0 }
        }
        if let string = raw as? String, !string.isEmpty {
            return humanize(string)
        }
        return nil
    }

    // MARK: - Legacy top-level keys (fallback)

    /// The pre-`limits` parse: the common Session + Weekly, plus the old model keys
    /// (now typically null) as `.model` scoped, plus any remaining utilization-bearing
    /// key humanized. Used only when the `limits` array is absent.
    private static func parseLegacyWindows(from root: [String: Any]) -> [UsageWindow] {
        var windows: [UsageWindow] = []
        var seen = Set<String>()

        for entry in knownWindowLabels {
            if let window = makeWindow(
                key: entry.key, kind: entry.kind, title: entry.title, scope: entry.scope,
                from: root)
            {
                windows.append(window)
                seen.insert(entry.key)
            }
        }
        // Any remaining utilization-bearing window — surfaced (humanized, general) so
        // nothing is hidden; a non-object sibling (e.g. the `limits` array itself, or
        // `extra_usage` without `utilization`) is simply skipped.
        for key in root.keys.sorted() where !seen.contains(key) {
            if let window = makeWindow(
                key: key, kind: .unknown, title: humanize(key), scope: .general, from: root)
            {
                windows.append(window)
            }
        }
        return windows
    }

    /// Legacy window key → (kind, friendly title, scope). Session/Weekly are general;
    /// the old model keys are `.model` scoped so they land in the scoped section too.
    private static let knownWindowLabels:
        [(key: String, kind: UsageWindowKind, title: String?, scope: UsageWindowScope)] = [
            ("five_hour", .fiveHour, nil, .general),
            ("seven_day", .weekly, nil, .general),
            ("seven_day_sonnet", .weekly, "Sonnet", .model("Sonnet")),
            ("seven_day_opus", .weekly, "Opus", .model("Opus")),
        ]

    private static func makeWindow(
        key: String, kind: UsageWindowKind, title: String?, scope: UsageWindowScope,
        from root: [String: Any]
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
            resetsAt: UsageHTTP.parseISODate(window["resets_at"] as? String),
            scope: scope,
            isActive: true)
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
