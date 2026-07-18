import Foundation
import SwiftData

/// Persists usage readings: appends one `UsageSnapshot` per window as history and
/// keeps each provider's `ProviderState` current (ARCHITECTURE §2, UsageStore
/// module). Keep-all retention for now — a retention policy is deferred
/// (ARCHITECTURE §11). `@MainActor` because the shared `ModelContext` is main-actor bound.
@MainActor
enum UsageStore {
    static func record(_ runtime: ProviderRuntime, for id: ProviderID, in modelContext: ModelContext) {
        let providerKey = id.rawValue
        let descriptor = FetchDescriptor<ProviderState>(
            predicate: #Predicate { $0.providerID == providerKey })

        let state: ProviderState
        if let existing = try? modelContext.fetch(descriptor).first {
            state = existing
        } else {
            state = ProviderState(providerID: providerKey, displayName: id.displayName, statusRaw: "")
            modelContext.insert(state)
        }
        state.statusRaw = runtime.connection.persistedRaw
        state.lastFetchedAt = runtime.lastFetched

        // Persist only the general Session/Weekly windows (Phase 17): scoped
        // model/surface limits are a live dashboard detail, kept out of history so
        // burn-rate/trend/plan-fit stay clean and no SwiftData migration is needed.
        for window in runtime.generalWindows {
            let snapshot = UsageSnapshot(
                providerID: providerKey,
                windowTypeRaw: window.kind.rawValue,
                used: window.used,
                limit: window.limit,
                resetsAt: window.resetsAt)
            snapshot.providerState = state
            modelContext.insert(snapshot)
        }

        try? modelContext.save()
    }
}
