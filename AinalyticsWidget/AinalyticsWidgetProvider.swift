import WidgetKit

/// One timeline entry: the moment, the usage snapshot read from the App Group, and
/// the user's widget configuration (provider + window choice).
struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedUsageSnapshot
    let configuration: AinalyticsWidgetConfiguration
}

/// Feeds the widget from the shared App Group snapshot. There is no networking here
/// — the main app does the polling and writes the derived snapshot; the widget only
/// reads it. The app also nudges `WidgetCenter` after each poll, so the timeline's
/// own cadence is a fallback for when the app is not running.
struct AinalyticsWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .placeholder, configuration: AinalyticsWidgetConfiguration())
    }

    func snapshot(for configuration: AinalyticsWidgetConfiguration, in context: Context) async -> UsageEntry {
        // The gallery preview shows representative data; the live widget reads real.
        let snapshot = context.isPreview ? .placeholder : SharedSnapshotStore.read()
        return UsageEntry(date: .now, snapshot: snapshot, configuration: configuration)
    }

    func timeline(for configuration: AinalyticsWidgetConfiguration, in context: Context) async -> Timeline<UsageEntry> {
        let entry = UsageEntry(
            date: .now, snapshot: SharedSnapshotStore.read(), configuration: configuration)
        // Re-read ~ every 15 minutes if the app never nudges us in the meantime.
        let next =
            Calendar.current.date(byAdding: .minute, value: 15, to: .now)
            ?? .now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(next))
    }
}

extension SharedUsageSnapshot {
    /// Representative sample for the widget gallery / Preview skeleton.
    static let placeholder = SharedUsageSnapshot(
        providers: [
            Provider(
                providerID: "claude", displayName: "Claude",
                windows: [
                    Window(kind: "fiveHour", title: nil, percentUsed: 3, resetsAt: .now.addingTimeInterval(3 * 3600)),
                    Window(kind: "weekly", title: nil, percentUsed: 69, resetsAt: .now.addingTimeInterval(4 * 86400)),
                    Window(
                        kind: "unknown", title: "Sonnet", percentUsed: 0, resetsAt: .now.addingTimeInterval(4 * 86400)),
                ]),
            Provider(
                providerID: "codex", displayName: "Codex",
                windows: [
                    Window(kind: "monthly", title: nil, percentUsed: 9, resetsAt: .now.addingTimeInterval(20 * 86400))
                ]),
            Provider(
                providerID: "gemini", displayName: "Gemini",
                windows: [
                    Window(kind: "fiveHour", title: nil, percentUsed: 88, resetsAt: .now.addingTimeInterval(90 * 60))
                ]),
        ],
        pinnedProviderID: "claude",
        updatedAt: .now)
}
