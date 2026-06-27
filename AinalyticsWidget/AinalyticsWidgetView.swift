import SwiftUI
import WidgetKit

/// Routes the widget family to its layout. Both honour the configuration (provider +
/// window) and show **remaining** ("% left"), matching the app's language; the bar
/// fills with what's *used* and tints amber/red near the limit. Falls back to an
/// honest empty state when nothing is connected.
struct AinalyticsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallUsageWidget(snapshot: entry.snapshot, config: entry.configuration)
        default: MediumUsageWidget(snapshot: entry.snapshot, config: entry.configuration)
        }
    }
}

// MARK: - Small

/// One provider + one window. The provider is the configured one (or, for Automatic,
/// the menu-bar-pinned provider, else the one closest to its limit); the window is the
/// configured metric (falling back to the provider's binding window when absent).
private struct SmallUsageWidget: View {
    let snapshot: SharedUsageSnapshot
    let config: AinalyticsWidgetConfiguration

    var body: some View {
        if let provider = snapshot.headlineProvider(for: config.provider),
            let window = provider.window(for: config.window.metric)
        {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(SharedBrand.accent(forProviderRaw: provider.providerID))
                        .frame(width: 8, height: 8)
                    Text(provider.displayName)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                WidgetText.windowLabel(window)
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(WidgetText.remaining(window.percentUsed)) left")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.7).lineLimit(1)
                UsageMeter(percentUsed: window.percentUsed, providerRaw: provider.providerID)
                if let reset = window.resetsAt {
                    ResetCaption(resetsAt: reset)
                }
            }
        } else {
            EmptyWidgetState()
        }
    }
}

// MARK: - Medium

/// Automatic provider → all connected providers as rows (the configured window each).
/// A specific provider → that provider's own windows as rows. Either way: name/label,
/// a meter, and the remaining percent.
private struct MediumUsageWidget: View {
    let snapshot: SharedUsageSnapshot
    let config: AinalyticsWidgetConfiguration

    var body: some View {
        if let single = config.provider.providerRaw {
            // A specific provider: break it down by its own windows.
            if let provider = snapshot.providers.first(where: { $0.providerID == single }),
                !provider.windows.isEmpty
            {
                VStack(alignment: .leading, spacing: 10) {
                    header(provider.displayName, accentRaw: provider.providerID)
                    ForEach(provider.windows) { window in
                        WindowUsageRow(
                            label: WidgetText.windowLabel(window), window: window,
                            providerRaw: provider.providerID)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                EmptyWidgetState()
            }
        } else {
            // Automatic: one row per connected provider, the configured window each.
            if snapshot.providers.isEmpty {
                EmptyWidgetState()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ainalytics").font(.headline)
                    ForEach(snapshot.providers.prefix(3)) { provider in
                        if let window = provider.window(for: config.window.metric) {
                            WindowUsageRow(
                                label: Text(provider.displayName), window: window,
                                providerRaw: provider.providerID)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func header(_ title: String, accentRaw: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(SharedBrand.accent(forProviderRaw: accentRaw)).frame(width: 8, height: 8)
            Text(title).font(.headline).lineLimit(1)
        }
    }
}

/// A labelled usage row: a lead label (provider name or window label), a meter, and
/// the remaining percent.
private struct WindowUsageRow: View {
    let label: Text
    let window: SharedUsageSnapshot.Window
    let providerRaw: String

    var body: some View {
        HStack(spacing: 8) {
            label
                .font(.subheadline).lineLimit(1)
                .frame(width: 116, alignment: .leading)
            UsageMeter(percentUsed: window.percentUsed, providerRaw: providerRaw)
            Text("\(WidgetText.remaining(window.percentUsed)) left")
                .font(.subheadline.weight(.medium)).monospacedDigit().lineLimit(1)
                .frame(width: 78, alignment: .trailing)
        }
    }
}

// MARK: - Shared pieces

/// A thin usage bar, filled with what's *used* and tinted accent → amber → red as the
/// limit nears — the app's severity language (the numeric remaining is shown alongside).
private struct UsageMeter: View {
    let percentUsed: Double
    let providerRaw: String

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(SharedBrand.usageTint(percentUsed: percentUsed, providerRaw: providerRaw))
                    .frame(width: max(0, min(1, percentUsed / 100)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}

/// A self-updating "resets in …" caption (the relative time is auto-localized).
private struct ResetCaption: View {
    let resetsAt: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
            Text(resetsAt, style: .relative)
        }
        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }
}

private struct EmptyWidgetState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No data yet").font(.subheadline.weight(.medium))
            Text("Open the app to connect.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Text helpers

private enum WidgetText {
    /// Remaining percent (100 − used) formatted for the locale, e.g. "%97" / "97%".
    static func remaining(_ percentUsed: Double) -> String {
        (max(0, 100 - percentUsed) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// A window's label: its model title verbatim, else the localized kind.
    static func windowLabel(_ window: SharedUsageSnapshot.Window) -> Text {
        if let title = window.title, !title.isEmpty { return Text(verbatim: title) }
        switch window.kind {
        case "fiveHour": return Text("Session")
        case "weekly": return Text("Weekly")
        case "monthly": return Text("Monthly")
        default: return Text(verbatim: "—")
        }
    }
}

extension SharedUsageSnapshot {
    /// The provider the small widget headlines: the configured one, or — for Automatic
    /// — the menu-bar-pinned provider, else the one closest to its limit.
    func headlineProvider(for choice: ProviderChoice) -> Provider? {
        if let raw = choice.providerRaw {
            return providers.first { $0.providerID == raw }
        }
        if let pinned = pinnedProviderID, let match = providers.first(where: { $0.providerID == pinned }) {
            return match
        }
        return providers.max { ($0.bindingWindow?.percentUsed ?? 0) < ($1.bindingWindow?.percentUsed ?? 0) }
    }
}

#Preview("Small", as: .systemSmall) {
    AinalyticsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder, configuration: AinalyticsWidgetConfiguration())
    UsageEntry(date: .now, snapshot: .empty, configuration: AinalyticsWidgetConfiguration())
}

#Preview("Medium", as: .systemMedium) {
    AinalyticsWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .placeholder, configuration: AinalyticsWidgetConfiguration())
}
