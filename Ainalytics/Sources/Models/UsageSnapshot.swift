import Foundation
import SwiftData

/// A point-in-time usage reading for one provider window.
///
/// The history of these powers trends and the snapshot-fed heatmap (Phase 4/5).
/// `providerID` and `windowTypeRaw` store the `rawValue` of `ProviderID` /
/// `UsageWindowKind` (SwiftData persists primitives; typed accessors live on the
/// enums).
@Model
final class UsageSnapshot {
    var providerID: String
    var capturedAt: Date
    var windowTypeRaw: String
    var used: Double
    var limit: Double
    var resetsAt: Date?

    var providerState: ProviderState?

    init(
        providerID: String,
        capturedAt: Date = .now,
        windowTypeRaw: String,
        used: Double,
        limit: Double,
        resetsAt: Date? = nil
    ) {
        self.providerID = providerID
        self.capturedAt = capturedAt
        self.windowTypeRaw = windowTypeRaw
        self.used = used
        self.limit = limit
        self.resetsAt = resetsAt
    }
}
