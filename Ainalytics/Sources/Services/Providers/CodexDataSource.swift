import Foundation

/// Codex (OpenAI / ChatGPT) usage data source.
///
/// Credential at `~/.codex/auth.json` (plain JSON, no keychain). Read-only.
///
/// Usage endpoint contract (verified against steipete/CodexBar):
/// `GET chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer` and,
/// when present, `ChatGPT-Account-Id`. The response carries
/// `rate_limit.primary_window` / `secondary_window`, each with `used_percent`
/// (percent used), `reset_at` (absolute Unix seconds), and `limit_window_seconds`.
/// There is no usable expiry timestamp in the file, so an expired token surfaces
/// only as a 401/403 → `.tokenExpired` (we never refresh — read-only policy).
struct CodexDataSource: UsageDataSource {
    let id: ProviderID = .codex

    private static let credentialFile = "~/.codex/auth.json"
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let userAgent = "codex_cli_rs/0.141.0"

    /// Window lengths (seconds) → kind. Plans differ: Pro/Plus expose 5-hour +
    /// weekly (+ per-model `additional_rate_limits`); the Go plan exposes a single
    /// 30-day monthly window. (additional_rate_limits is wired when we can test a
    /// Pro/Plus response — it is null on the Go plan.)
    private static let fiveHourSeconds: Double = 18_000
    private static let weeklySeconds: Double = 604_800
    private static let monthlySeconds: Double = 2_592_000

    func detectConnection() async -> ProviderConnection {
        TokenLocator.fileExists(at: Self.credentialFile) ? .connected : .notInstalled
    }

    func fetchUsage() async throws -> UsageReport {
        let credentials = try readCredentials()

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let accountID = credentials.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let data = try await UsageHTTP.data(for: request)
        let raw = UsageHTTP.prettyJSON(from: data)

        let dto: CodexUsageDTO
        do {
            dto = try JSONDecoder().decode(CodexUsageDTO.self, from: data)
        } catch {
            throw UsageDataSourceError.endpoint("Decoding failed: \(error.localizedDescription)")
        }

        let windows = [dto.rateLimit?.primaryWindow, dto.rateLimit?.secondaryWindow]
            .compactMap { $0 }
            .compactMap(Self.mapWindow)

        return UsageReport(windows: windows, rawResponse: raw)
    }

    private static func mapWindow(_ window: CodexUsageDTO.Window) -> UsageWindow? {
        guard let usedPercent = window.usedPercent else { return nil }
        let kind: UsageWindowKind
        switch window.limitWindowSeconds {
        case Self.fiveHourSeconds: kind = .fiveHour
        case Self.weeklySeconds: kind = .weekly
        case Self.monthlySeconds: kind = .monthly
        default: kind = .unknown
        }
        let resetsAt = window.resetAt.map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(
            id: kind.rawValue,
            kind: kind,
            title: nil,
            used: usedPercent,
            limit: 100,
            resetsAt: resetsAt
        )
    }

    private func readCredentials() throws -> (accessToken: String, accountID: String?) {
        guard let data = TokenLocator.readFileData(at: Self.credentialFile) else {
            throw UsageDataSourceError.notInstalled
        }
        guard let auth = try? JSONDecoder().decode(CodexAuth.self, from: data) else {
            throw UsageDataSourceError.credentialUnreadable
        }
        // Prefer the OAuth access token; fall back to a legacy top-level API key.
        if let token = auth.tokens?.accessToken, !token.isEmpty {
            return (token, auth.tokens?.accountID)
        }
        if let apiKey = auth.openAIAPIKey, !apiKey.isEmpty {
            return (apiKey, auth.tokens?.accountID)
        }
        throw UsageDataSourceError.credentialUnreadable
    }
}

// MARK: - DTOs

/// Credential JSON: `{ "tokens": { "access_token", "account_id" }, "OPENAI_API_KEY" }`.
private struct CodexAuth: Decodable {
    let tokens: Tokens?
    let openAIAPIKey: String?

    struct Tokens: Decodable {
        let accessToken: String?
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountID = "account_id"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tokens
        case openAIAPIKey = "OPENAI_API_KEY"
    }
}

/// Usage response: `{ "rate_limit": { "primary_window", "secondary_window" } }`.
private struct CodexUsageDTO: Decodable {
    let rateLimit: RateLimit?

    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double?
        /// Absolute Unix epoch seconds (not seconds-from-now).
        let resetAt: Double?
        let limitWindowSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }
}
