import Foundation

/// The App Group identifier shared by the main app and the widget extension.
///
/// macOS requires the **Team-ID prefix** on App Group identifiers (unlike iOS's
/// `group.` convention). This string MUST match the `com.apple.security.application-groups`
/// entitlement on BOTH targets and the identifier Beyazıt registers in the Developer
/// portal — if any of the three disagree, `containerURL(...)` returns `nil` and the
/// widget shows its empty state.
let ainalyticsAppGroupID = "2G7T76698G.com.beyazit.ainalytics"

/// A small, token-free usage snapshot the main app writes to the App Group
/// container for the widget to read. Holds only the derived per-window percentages
/// + reset dates the menu bar and dashboard already display — **never a token,
/// never message content** (ARCHITECTURE §3: the widget reads a derived snapshot).
struct SharedUsageSnapshot: Codable, Sendable {

    /// One rolling usage window (mirrors the app's `UsageWindow`, primitives only).
    struct Window: Codable, Sendable, Identifiable {
        var id: String { kind + (title ?? "") }
        /// `UsageWindowKind.rawValue` — "fiveHour" / "weekly" / "monthly" / "unknown".
        let kind: String
        /// A model-named window (e.g. "Sonnet"), else `nil` → use the kind label.
        let title: String?
        /// How much of the window is consumed, 0–100. Remaining = 100 − this.
        let percentUsed: Double
        /// When the window resets. `nil` → the window does not reset.
        let resetsAt: Date?
    }

    /// One provider's at-a-glance usage, with every window it reports.
    struct Provider: Codable, Sendable, Identifiable {
        var id: String { providerID }
        /// `ProviderID.rawValue` — keys the brand accent + identity in the widget.
        let providerID: String
        /// Display name resolved at write time (a proper noun; shown verbatim).
        let displayName: String
        /// All windows this provider reports, in the provider's own order.
        let windows: [Window]
    }

    /// Connected providers, in `ProviderID.allCases` order.
    let providers: [Provider]
    /// The menu-bar-pinned provider (Settings → General → Menu Bar), if any — the
    /// small widget headlines this one when its configuration is set to Automatic.
    let pinnedProviderID: String?
    /// When the main app last wrote this snapshot.
    let updatedAt: Date

    static let empty = SharedUsageSnapshot(providers: [], pinnedProviderID: nil, updatedAt: .distantPast)
}

/// Which usage window the widget headlines. The widget's `WindowChoice` configuration
/// maps onto this; the selection logic lives here so it is shared + unit-testable.
enum WindowMetric: String, Codable, Sendable, CaseIterable {
    case auto  // the binding constraint — the window closest to its limit
    case session  // the five-hour rolling window
    case weekly
    case monthly
}

extension SharedUsageSnapshot.Provider {
    /// The window closest to its limit (highest percent used) — the binding constraint.
    var bindingWindow: SharedUsageSnapshot.Window? {
        windows.max { $0.percentUsed < $1.percentUsed }
    }

    /// The window matching the chosen metric. Falls back to the binding constraint
    /// when the provider has no window of that kind (e.g. Codex reports only Monthly,
    /// so a `.session` request falls back to its Monthly window) — never `nil` while
    /// the provider has any window, so the widget always shows something honest.
    func window(for metric: WindowMetric) -> SharedUsageSnapshot.Window? {
        switch metric {
        case .auto: bindingWindow
        case .session: windows.first { $0.kind == "fiveHour" } ?? bindingWindow
        case .weekly: windows.first { $0.kind == "weekly" } ?? bindingWindow
        case .monthly: windows.first { $0.kind == "monthly" } ?? bindingWindow
        }
    }
}

/// Reads / writes the shared snapshot as atomic JSON in the App Group container.
/// The main app writes after each poll; the widget reads in its timeline. Both
/// targets must carry the `com.apple.security.application-groups` entitlement —
/// without it (even for the non-sandboxed main app) `containerURL(...)` is `nil`.
enum SharedSnapshotStore {
    private static let fileName = "usage-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ainalyticsAppGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Write the snapshot. Failure is non-fatal — the widget keeps its last good copy.
    static func write(_ snapshot: SharedUsageSnapshot) {
        guard let fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Read the last written snapshot, or `.empty` if none exists yet / is unreadable.
    static func read() -> SharedUsageSnapshot {
        guard let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let snapshot = try? JSONDecoder().decode(SharedUsageSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
}
