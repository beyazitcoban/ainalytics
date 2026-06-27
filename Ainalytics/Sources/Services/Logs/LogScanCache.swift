import Foundation

/// On-disk aggregate cache for the log scanner. Keyed by file path; each entry
/// records the file's size + mtime so an unchanged file is never re-parsed. The
/// CLI log tree can reach ~1 GB across hundreds of files, so a full re-scan on
/// every launch would be unacceptable — ARCHITECTURE §3 pre-authorized this
/// caching ("not duplicated into SwiftData unless caching proves necessary").
///
/// It stores only derived counts (tokens per day, tokens per model) — no message
/// content, no credential. Persisted as plain JSON beside the SwiftData store in
/// Application Support.
struct LogScanCache: Codable, Sendable {
    /// Bump when the aggregate shape changes so stale caches invalidate cleanly.
    /// v2 (Phase 10): added the per-hour-of-day bucket (`hours`) for peak-hours —
    /// a stale v1 cache is dropped and re-scanned once, which is acceptable.
    static let currentVersion = 2

    var version = LogScanCache.currentVersion
    /// File path → its parsed aggregate.
    var files: [String: FileAggregate] = [:]

    /// One parsed file's contribution: the size + mtime it was parsed at, plus the
    /// per-day, per-hour-of-day, and per-model token tallies extracted from it.
    struct FileAggregate: Codable, Sendable {
        /// `ProviderID.rawValue` of the tree this file belongs to.
        let provider: String
        let size: Int
        let mtime: Double
        /// Start-of-day epoch-seconds (as a string key) → counts on that day.
        var days: [String: DayCounts]
        /// Model id → summed token counts attributed to it.
        var models: [String: TokenCounts]
        /// Hour-of-day ("0"…"23", local) → counts in that hour, aggregated across
        /// the file's history. Powers the peak-hours insight (Phase 10).
        var hours: [String: HourCounts]
    }

    struct DayCounts: Codable, Sendable {
        var tokens: Int
        var messages: Int
    }

    /// Activity within one hour-of-day bucket. Same `{tokens, messages}` shape as
    /// `DayCounts`, kept as its own type so the per-hour data is self-documenting
    /// in the cache and at the merge site (Phase 10 — peak-hours).
    struct HourCounts: Codable, Sendable {
        var tokens: Int
        var messages: Int
    }

    struct TokenCounts: Codable, Sendable {
        var input: Int
        var output: Int
        var cacheRead: Int
        var cacheWrite: Int
    }
}
