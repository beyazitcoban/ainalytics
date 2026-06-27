import Foundation
import OSLog
import Observation
import SwiftData

/// Root application state: the provider registry and their live usage runtimes.
/// `@MainActor` because it backs the UI.
///
/// `AppState` owns *what* a refresh does — fetch each provider concurrently, map
/// the outcome to a `ProviderRuntime`, and persist snapshots. *When* it runs is
/// the `UsagePoller`'s job (interval + on-wake + manual).
@MainActor
@Observable
final class AppState {
    /// Current runtime per provider (connection + usage windows + metadata).
    private(set) var runtimes: [ProviderID: ProviderRuntime]

    /// The three concrete data sources (Critical Pass #2 — not a plugin registry).
    @ObservationIgnored private let sources: [any UsageDataSource]
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.beyazit.ainalytics", category: "providers")

    init(sources: [any UsageDataSource] = AppState.defaultSources) {
        self.sources = sources
        self.runtimes = Dictionary(
            uniqueKeysWithValues: ProviderID.allCases.map { ($0, ProviderRuntime.unknown) })
    }

    static var defaultSources: [any UsageDataSource] {
        [ClaudeDataSource(), CodexDataSource()]
    }

    func runtime(for id: ProviderID) -> ProviderRuntime {
        runtimes[id] ?? .unknown
    }

    /// Most-recent successful fetch across all providers (drives the "Updated …" label).
    var lastUpdated: Date? {
        runtimes.values.compactMap(\.lastFetched).max()
    }

    /// Build the small, token-free snapshot the widget reads from the App Group
    /// container (Phase 12). Includes every connected provider with all of its usage
    /// windows (so the widget can headline a user-chosen window) — the same percentages
    /// + resets the menu bar shows. No token, no message content. The `pinned` provider
    /// (menu-bar preference) is carried so the small widget can default to it.
    func sharedSnapshot(pinned: ProviderID?) -> SharedUsageSnapshot {
        let providers: [SharedUsageSnapshot.Provider] = ProviderID.allCases.compactMap { id in
            let runtime = runtime(for: id)
            guard runtime.connection.isConnected, !runtime.windows.isEmpty else { return nil }
            let windows = runtime.windows.map { window in
                SharedUsageSnapshot.Window(
                    kind: window.kind.rawValue,
                    title: window.title,
                    percentUsed: window.percentUsed,
                    resetsAt: window.resetsAt)
            }
            return SharedUsageSnapshot.Provider(
                providerID: id.rawValue, displayName: id.displayName, windows: windows)
        }
        return SharedUsageSnapshot(
            providers: providers, pinnedProviderID: pinned?.rawValue, updatedAt: .now)
    }

    /// Refresh every provider concurrently. One provider failing never blocks the
    /// others (graceful degradation — ARCHITECTURE §10). When a `ModelContext` is
    /// given, successful readings are persisted as `UsageSnapshot` history.
    /// Logs only the provider id + resulting state — never the token value.
    /// `enabled` (when given) restricts the refresh to those providers — disabled
    /// ones are not fetched and their runtime is cleared so the UI and
    /// notifications never see stale data for a provider the user turned off.
    func refreshAll(persistTo modelContext: ModelContext? = nil, enabled: Set<ProviderID>? = nil) async {
        let sources: [any UsageDataSource]
        if let enabled {
            sources = self.sources.filter { enabled.contains($0.id) }
            for id in ProviderID.allCases where !enabled.contains(id) {
                runtimes[id] = .unknown
            }
        } else {
            sources = self.sources
        }
        let results = await withTaskGroup(of: (ProviderID, ProviderRuntime).self) { group in
            for source in sources {
                group.addTask { await Self.fetch(from: source) }
            }
            var collected: [(ProviderID, ProviderRuntime)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        for (id, runtime) in results {
            runtimes[id] = runtime
            logger.notice(
                "Provider \(id.rawValue, privacy: .public): \(runtime.connection.persistedRaw, privacy: .public)"
            )
            if let modelContext {
                UsageStore.record(runtime, for: id, in: modelContext)
            }
        }
    }

    /// Fetch one provider off the main actor and map any failure to a runtime.
    private nonisolated static func fetch(from source: any UsageDataSource) async -> (
        ProviderID, ProviderRuntime
    ) {
        let connection = await source.detectConnection()
        guard connection != .notInstalled else {
            return (source.id, ProviderRuntime.unknown.with(connection: .notInstalled))
        }
        do {
            let report = try await source.fetchUsage()
            // 2xx but nothing recognizable → surface the raw body in the Debug view
            // (Critical Pass #4) instead of silently showing "connected, no data".
            if report.windows.isEmpty {
                return (
                    source.id,
                    ProviderRuntime(
                        connection: .endpointError("No usage windows parsed"), windows: [],
                        lastFetched: .now, errorMessage: "No usage windows parsed",
                        rawResponse: report.rawResponse)
                )
            }
            return (
                source.id,
                ProviderRuntime(
                    connection: .connected, windows: report.windows, lastFetched: .now,
                    errorMessage: nil, rawResponse: report.rawResponse)
            )
        } catch UsageDataSourceError.notInstalled {
            return (source.id, ProviderRuntime.unknown.with(connection: .notInstalled))
        } catch UsageDataSourceError.tokenExpired {
            return (
                source.id,
                ProviderRuntime(
                    connection: .tokenExpired, windows: [], lastFetched: .now, errorMessage: nil,
                    rawResponse: nil)
            )
        } catch let UsageDataSourceError.endpoint(message) {
            return (source.id, Self.failureRuntime(message))
        } catch UsageDataSourceError.credentialUnreadable {
            return (source.id, Self.failureRuntime("Credential unreadable"))
        } catch {
            return (source.id, Self.failureRuntime(error.localizedDescription))
        }
    }

    private nonisolated static func failureRuntime(_ message: String) -> ProviderRuntime {
        ProviderRuntime(
            connection: .endpointError(message), windows: [], lastFetched: .now,
            errorMessage: message, rawResponse: nil)
    }
}

extension ProviderRuntime {
    /// Returns a copy with a different connection state (keeps this a value type
    /// while avoiding repeated full initializers in the failure-mapping above).
    fileprivate func with(connection: ProviderConnection) -> ProviderRuntime {
        var copy = self
        copy.connection = connection
        return copy
    }
}

#if DEBUG
    extension AppState {
        /// Builds an `AppState` with fixed runtimes for SwiftUI Previews. Same-file
        /// access lets it set the `private(set)` runtimes.
        static func preview(_ runtimes: [ProviderID: ProviderRuntime]) -> AppState {
            let state = AppState()
            state.runtimes = runtimes
            return state
        }
    }
#endif
