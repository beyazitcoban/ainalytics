import Foundation
import SwiftData

/// Per-provider persisted status + last-fetch metadata, so the UI can render
/// degraded states reliably across launches. `providerID` is the unique key
/// (one row per provider).
@Model
final class ProviderState {
    @Attribute(.unique) var providerID: String
    var displayName: String
    var statusRaw: String
    var lastFetchedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \UsageSnapshot.providerState)
    var snapshots: [UsageSnapshot] = []

    init(
        providerID: String,
        displayName: String,
        statusRaw: String,
        lastFetchedAt: Date? = nil
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.statusRaw = statusRaw
        self.lastFetchedAt = lastFetchedAt
    }
}
