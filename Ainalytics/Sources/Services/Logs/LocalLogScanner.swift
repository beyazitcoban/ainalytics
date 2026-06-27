import Foundation
import OSLog

/// Scans the local CLI session JSONL logs for per-day activity (the GitHub-style
/// heatmap) and per-model token counts (the cost engine). Shared infrastructure
/// for both (ARCHITECTURE §2 / §10) — built once in Phase 5.
///
/// Two trees are read, both under the user's home (no TCC permission needed):
/// - Claude: `~/.claude/projects/**/*.jsonl`  (`message.usage` on `assistant` rows)
/// - Codex:  `~/.codex/sessions/**/*.jsonl`   (`token_count` events; model from `turn_context`)
///
/// The `actor` is shaped so a future token-bearing source slots in as one more
/// tree.
///
/// An `actor` because the tree can reach ~1 GB: scanning runs off the main actor,
/// streams each file line-by-line (a 30 MB file is never loaded whole), and only
/// the handful of numeric fields per line are kept — message content is discarded
/// immediately. Unchanged files are skipped via the on-disk `LogScanCache`.
actor LocalLogScanner {
    /// How far back the heatmap (and therefore the scan) reaches. 53 weeks gives
    /// the familiar full-year GitHub grid; files untouched since before the cutoff
    /// are never opened.
    static let windowDays = 53 * 7

    private let logger = Logger(subsystem: "com.beyazit.ainalytics", category: "logscan")
    private let fileManager = FileManager.default
    private lazy var isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var cache = LogScanCache()
    private var cacheLoaded = false

    /// Scan both trees and return the merged result. Never throws — a single
    /// unreadable file is logged and skipped (graceful degradation); a missing
    /// tree simply contributes nothing.
    func scan() async -> LogScanResult {
        loadCacheIfNeeded()
        let cutoff = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: .now) ?? .distantPast)

        let discovered =
            discoverFiles(in: claudeRoot, provider: .claude)
            + discoverFiles(in: codexRoot, provider: .codex)

        var seenPaths = Set<String>()
        for file in discovered {
            seenPaths.insert(file.path)
            // No in-window activity → never open the file.
            if file.mtime < cutoff.timeIntervalSince1970 { continue }
            // Cache hit (same size + mtime) → reuse the parsed aggregate.
            if let cached = cache.files[file.path], cached.size == file.size,
                abs(cached.mtime - file.mtime) < 1
            {
                continue
            }
            let aggregate = await parse(file)
            cache.files[file.path] = aggregate
        }
        // Drop cache entries for files that no longer exist.
        cache.files = cache.files.filter { seenPaths.contains($0.key) }
        persistCache()

        return merge(cutoff: cutoff)
    }

    // MARK: - Discovery

    private var claudeRoot: URL {
        fileManager.homeDirectoryForCurrentUser.appending(path: ".claude/projects")
    }
    private var codexRoot: URL {
        fileManager.homeDirectoryForCurrentUser.appending(path: ".codex/sessions")
    }

    private struct DiscoveredFile {
        let url: URL
        let path: String
        let provider: ProviderID
        let size: Int
        let mtime: Double
    }

    private func discoverFiles(in root: URL, provider: ProviderID) -> [DiscoveredFile] {
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .fileSizeKey, .contentModificationDateKey, .isRegularFileKey,
                ],
                options: [.skipsHiddenFiles])
        else { return [] }

        var files: [DiscoveredFile] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard
                let values = try? url.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey, .isRegularFileKey,
                ]),
                values.isRegularFile == true,
                let size = values.fileSize,
                let mtime = values.contentModificationDate
            else { continue }
            files.append(
                DiscoveredFile(
                    url: url, path: url.path(percentEncoded: false), provider: provider,
                    size: size, mtime: mtime.timeIntervalSince1970))
        }
        return files
    }

    // MARK: - Parsing

    private func parse(_ file: DiscoveredFile) async -> LogScanCache.FileAggregate {
        let parsed: ParsedFile
        switch file.provider {
        case .claude: parsed = await parseClaude(file.url)
        case .codex: parsed = await parseCodex(file.url)
        }
        return LogScanCache.FileAggregate(
            provider: file.provider.rawValue, size: file.size, mtime: file.mtime,
            days: parsed.dayCounts, models: parsed.modelCounts, hours: parsed.hourCounts)
    }

    /// Accumulator a single file folds into — string-keyed to match the cache shape.
    private struct ParsedFile {
        var dayCounts: [String: LogScanCache.DayCounts] = [:]
        var modelCounts: [String: LogScanCache.TokenCounts] = [:]
        var hourCounts: [String: LogScanCache.HourCounts] = [:]

        mutating func add(
            day: Date, model: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int
        ) {
            let calendar = Calendar.current
            let tokens = input + output + cacheRead + cacheWrite

            let dayKey = String(Int(calendar.startOfDay(for: day).timeIntervalSince1970))
            var d = dayCounts[dayKey] ?? LogScanCache.DayCounts(tokens: 0, messages: 0)
            d.tokens += tokens
            d.messages += 1
            dayCounts[dayKey] = d

            // Hour-of-day bucket (0–23, local) — the peak-hours insight (Phase 10).
            let hourKey = String(calendar.component(.hour, from: day))
            var h = hourCounts[hourKey] ?? LogScanCache.HourCounts(tokens: 0, messages: 0)
            h.tokens += tokens
            h.messages += 1
            hourCounts[hourKey] = h

            var m =
                modelCounts[model]
                ?? LogScanCache.TokenCounts(
                    input: 0, output: 0, cacheRead: 0, cacheWrite: 0)
            m.input += input
            m.output += output
            m.cacheRead += cacheRead
            m.cacheWrite += cacheWrite
            modelCounts[model] = m
        }
    }

    /// Claude: one `assistant` row per API message, but a single `requestId` can
    /// repeat across streamed rows with the same (final) usage — so usage is
    /// de-duplicated per `requestId` (max per field) before folding, to avoid the
    /// ~5× over-count seen in the raw logs.
    private func parseClaude(_ url: URL) async -> ParsedFile {
        struct Pending {
            var model: String
            var day: Date
            var input: Int
            var output: Int
            var cacheWrite: Int  // cache_creation_input_tokens
            var cacheRead: Int  // cache_read_input_tokens
        }
        var byRequest: [String: Pending] = [:]

        do {
            for try await line in url.lines {
                guard line.contains("\"usage\"") else { continue }  // cheap prefilter
                guard let data = line.data(using: .utf8),
                    let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    obj["type"] as? String == "assistant",
                    let message = obj["message"] as? [String: Any],
                    let usage = message["usage"] as? [String: Any]
                else { continue }

                let model = message["model"] as? String ?? ""
                guard !model.isEmpty, model != "<synthetic>" else { continue }
                guard let timestamp = obj["timestamp"] as? String,
                    let date = isoFormatter.date(from: timestamp)
                else { continue }

                let requestId =
                    (obj["requestId"] as? String) ?? (message["id"] as? String)
                    ?? UUID().uuidString
                let input = Self.int(usage["input_tokens"])
                let output = Self.int(usage["output_tokens"])
                let cacheWrite = Self.int(usage["cache_creation_input_tokens"])
                let cacheRead = Self.int(usage["cache_read_input_tokens"])

                if let existing = byRequest[requestId] {
                    byRequest[requestId] = Pending(
                        model: existing.model, day: existing.day,
                        input: max(existing.input, input), output: max(existing.output, output),
                        cacheWrite: max(existing.cacheWrite, cacheWrite),
                        cacheRead: max(existing.cacheRead, cacheRead))
                } else {
                    byRequest[requestId] = Pending(
                        model: model, day: date, input: input, output: output,
                        cacheWrite: cacheWrite, cacheRead: cacheRead)
                }
            }
        } catch {
            logger.error("Claude log unreadable: \(error.localizedDescription, privacy: .public)")
        }

        var parsed = ParsedFile()
        for pending in byRequest.values {
            parsed.add(
                day: pending.day, model: pending.model, input: pending.input,
                output: pending.output, cacheRead: pending.cacheRead, cacheWrite: pending.cacheWrite)
        }
        return parsed
    }

    /// Codex: `token_count` events carry `last_token_usage` (the per-turn delta —
    /// summed gives the session total); the model is announced in `turn_context`
    /// and tracked as the stream advances. Token-count events seen before any
    /// model is known are held and flushed once the model appears.
    private func parseCodex(_ url: URL) async -> ParsedFile {
        struct Turn {
            let day: Date
            let input: Int
            let output: Int
            let cacheRead: Int
        }
        var parsed = ParsedFile()
        var currentModel: String?
        var pending: [Turn] = []

        func flush(_ turn: Turn, model: String) {
            parsed.add(
                day: turn.day, model: model, input: turn.input, output: turn.output,
                cacheRead: turn.cacheRead, cacheWrite: 0)
        }

        do {
            for try await line in url.lines {
                let hasTurnContext = line.contains("\"turn_context\"")
                let hasTokenCount = line.contains("token_count")
                guard hasTurnContext || hasTokenCount else { continue }
                guard let data = line.data(using: .utf8),
                    let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let payload = obj["payload"] as? [String: Any]
                else { continue }

                if hasTurnContext, let model = payload["model"] as? String, !model.isEmpty {
                    currentModel = model
                    for turn in pending { flush(turn, model: model) }
                    pending.removeAll()
                    continue
                }

                guard payload["type"] as? String == "token_count",
                    let info = payload["info"] as? [String: Any],
                    let last = info["last_token_usage"] as? [String: Any],
                    let timestamp = obj["timestamp"] as? String,
                    let date = isoFormatter.date(from: timestamp)
                else { continue }

                let totalInput = Self.int(last["input_tokens"])
                let cachedInput = Self.int(last["cached_input_tokens"])
                let uncachedInput = max(0, totalInput - cachedInput)
                let output = Self.int(last["output_tokens"]) + Self.int(last["reasoning_output_tokens"])
                let turn = Turn(
                    day: date, input: uncachedInput, output: output, cacheRead: cachedInput)

                if let model = currentModel {
                    flush(turn, model: model)
                } else {
                    pending.append(turn)
                }
            }
        } catch {
            logger.error("Codex log unreadable: \(error.localizedDescription, privacy: .public)")
        }

        // Token counts with no model announced anywhere → "unknown" (priced as
        // unavailable rather than guessed).
        for turn in pending { flush(turn, model: currentModel ?? "unknown") }
        return parsed
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    // MARK: - Merge

    private func merge(cutoff: Date) -> LogScanResult {
        var dayMap: [Date: DayActivity] = [:]
        var hourMap: [Int: HourActivity] = [:]
        var modelMap: [String: ModelUsage] = [:]

        for aggregate in cache.files.values {
            guard let provider = ProviderID(rawValue: aggregate.provider) else { continue }
            for (dayKey, counts) in aggregate.days {
                guard let epoch = Double(dayKey) else { continue }
                let day = Date(timeIntervalSince1970: epoch)
                guard day >= cutoff else { continue }
                var entry =
                    dayMap[day]
                    ?? DayActivity(day: day, tokensByProvider: [:], messagesByProvider: [:])
                entry.tokensByProvider[provider, default: 0] += counts.tokens
                entry.messagesByProvider[provider, default: 0] += counts.messages
                dayMap[day] = entry
            }
            // Hour-of-day buckets are a time-of-day distribution (not date-bounded),
            // so they aggregate across every in-window file — there is no per-hour
            // date to filter by the cutoff.
            for (hourKey, counts) in aggregate.hours {
                guard let hour = Int(hourKey), (0...23).contains(hour) else { continue }
                var entry =
                    hourMap[hour]
                    ?? HourActivity(hour: hour, tokensByProvider: [:], messagesByProvider: [:])
                entry.tokensByProvider[provider, default: 0] += counts.tokens
                entry.messagesByProvider[provider, default: 0] += counts.messages
                hourMap[hour] = entry
            }
            for (model, tc) in aggregate.models {
                let key = "\(provider.rawValue)/\(model)"
                var usage =
                    modelMap[key]
                    ?? ModelUsage(
                        provider: provider, model: model, inputTokens: 0, outputTokens: 0,
                        cacheReadTokens: 0, cacheWriteTokens: 0)
                usage.inputTokens += tc.input
                usage.outputTokens += tc.output
                usage.cacheReadTokens += tc.cacheRead
                usage.cacheWriteTokens += tc.cacheWrite
                modelMap[key] = usage
            }
        }

        return LogScanResult(
            days: dayMap.values.sorted { $0.day < $1.day },
            models: modelMap.values.filter { $0.totalTokens > 0 }.sorted {
                $0.totalTokens > $1.totalTokens
            },
            hours: hourMap.values.sorted { $0.hour < $1.hour })
    }

    // MARK: - Cache persistence

    private var cacheURL: URL? {
        guard
            let support = try? fileManager.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                create: true)
        else { return nil }
        let dir = support.appending(path: "Ainalytics", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "LogScanCache.json")
    }

    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let url = cacheURL, let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(LogScanCache.self, from: data),
            decoded.version == LogScanCache.currentVersion
        else { return }
        cache = decoded
    }

    private func persistCache() {
        guard let url = cacheURL else { return }
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
