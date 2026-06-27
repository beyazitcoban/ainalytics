import Foundation

/// Shared HTTP plumbing for the three provider usage endpoints.
///
/// Centralizes status-code → error mapping so every data source degrades the same
/// way (graceful degradation, ARCHITECTURE §10): 401/403 means the stored token is
/// no longer valid → `.tokenExpired` (the app never refreshes — read-only policy),
/// any other non-2xx or transport failure → `.endpoint`.
enum UsageHTTP {

    /// Performs the request and returns the body on a 2xx response.
    /// Throws `UsageDataSourceError` (never a raw URLError) so callers map outcomes
    /// to a `ProviderConnection` uniformly.
    static func data(for request: URLRequest, session: URLSession = .shared) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageDataSourceError.endpoint(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageDataSourceError.endpoint("Non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw UsageDataSourceError.tokenExpired
        default:
            throw UsageDataSourceError.endpoint("HTTP \(http.statusCode)")
        }
    }

    /// Parses an ISO-8601 timestamp, tolerant of fractional seconds. Returns nil on failure.
    /// (Claude `resets_at` is ISO-8601; Codex `reset_at` is Unix seconds and does
    /// not use this.)
    static func parseISODate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// Pretty-prints a raw JSON body for the Debug raw-data view. Falls back to the
    /// UTF-8 string, then to nil. Used only for in-memory display — never persisted.
    static func prettyJSON(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: pretty, encoding: .utf8)
        {
            return string
        }
        return String(data: data, encoding: .utf8)
    }
}
