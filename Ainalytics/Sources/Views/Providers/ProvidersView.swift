import SwiftUI

/// Lists each provider with its live usage. Each provider can expose several
/// limit windows (e.g. Claude's 5-hour Session + 7-day Weekly); all parsed
/// windows render, each with its own bar + reset countdown. Degraded states
/// (not installed, token expired, connection lost) show clearly — icon + text +
/// colour, never colour alone (code-principles §7).
struct ProvidersView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppPreferences.self) private var preferences

    /// The popover caps the provider list at this height and scrolls beyond it;
    /// below the cap the list fits its content, so disabling a provider never leaves
    /// an empty gap at the bottom of the popover.
    private static let maxListHeight: CGFloat = 320
    @State private var contentHeight: CGFloat?

    /// Providers shown in the popover. When a provider is pinned to the menu bar
    /// (Settings → General → Menu Bar), the popover focuses on just that one;
    /// otherwise it lists every enabled provider.
    private var displayedProviders: [ProviderID] {
        if let pinned = preferences.menuBarProvider {
            return [pinned]
        }
        return preferences.enabledProviderIDs
    }

    var body: some View {
        if displayedProviders.isEmpty {
            ContentUnavailableView {
                Label("No providers tracked", systemImage: "eye.slash")
            } description: {
                Text("Enable a provider in Settings → Providers.")
            }
        } else {
            ScrollView {
                // A hairline `Divider` separates providers (none after the last); the
                // surrounding `lg` spacing keeps it from reading as a heavy rule — the
                // restrained Tahoe idiom, not a thick web-style line.
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(Array(displayedProviders.enumerated()), id: \.element) { index, id in
                        ProviderRow(id: id, runtime: appState.runtime(for: id))
                        if index < displayedProviders.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    contentHeight = $0
                }
            }
            // Fit the content, capped at `maxListHeight` (scrolls past it). Keeps the
            // popover snug when few providers are shown — no trailing empty gap.
            .frame(height: min(contentHeight ?? Self.maxListHeight, Self.maxListHeight))
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// A single provider: an accent brand swatch + name (with a degraded-state chip),
/// then one usage block per limit window indented beneath it (when connected).
struct ProviderRow: View {
    @Environment(AppPreferences.self) private var preferences
    let id: ProviderID
    let runtime: ProviderRuntime

    private static let glyphSize: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header

            if runtime.connection.isConnected {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    // Menu bar shows only the plan-wide Session/Weekly (general) windows;
                    // model/surface-scoped Claude limits live on the dashboard (Phase 17).
                    ForEach(runtime.generalWindows) { window in
                        windowBlock(window)
                    }
                }
                .padding(.leading, Self.glyphSize + Theme.Spacing.md)  // align under the name
            } else if runtime.connection == .tokenExpired {
                Text("Re-login in your CLI to reconnect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Self.glyphSize + Theme.Spacing.md)
            } else if runtime.connection == .noTrackableUsage {
                Text("This plan doesn't report a trackable usage limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Self.glyphSize + Theme.Spacing.md)
            }
        }
    }

    /// Accent brand swatch + name; a degraded provider trades its usage blocks for a
    /// status chip (icon + text + colour — never colour alone, code-principles §7).
    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProviderLogo(id: id, size: Self.glyphSize)

            Text(id.displayName)
                .font(.body.weight(.semibold))

            Spacer(minLength: Theme.Spacing.sm)

            if !runtime.connection.isConnected {
                ConnectionStatusChip(connection: runtime.connection)
            }
        }
    }

    /// One limit window: label + percent remaining, the `UsageBar`, and a live reset countdown.
    @ViewBuilder private func windowBlock(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                window.labelText
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Self.percentRemainingText(window)) left")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            UsageBar(percentUsed: window.percentUsed, accent: Theme.accent(for: id))
            if let resetsAt = window.resetsAt {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "clock")
                        .imageScale(.small)
                    // The shared formatter renders this per the user's "Reset display"
                    // preference: a relative, self-updating countdown ("%@ sonra
                    // sıfırlanır") or an absolute time ("%@'da sıfırlanır"). The
                    // relative branch keeps the live countdown via the interpolated date.
                    ResetTimeFormatter.text(
                        for: resetsAt, style: preferences.resetDisplayStyle, phrasing: .reset)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(window.labelText)
        .accessibilityValue(Text("\(Self.percentRemainingText(window)) left"))
    }

    /// Locale-aware percent remaining (e.g. "72%"). Formatting through `.percent`
    /// keeps the `%` inside the argument, so the localizable key stays "%@ left".
    private static func percentRemainingText(_ window: UsageWindow) -> String {
        (window.percentRemaining / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}

/// UI labels for window kinds (view layer — keeps the model type UI-framework-free).
extension UsageWindowKind {
    var label: LocalizedStringKey {
        switch self {
        case .fiveHour: "Session"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .unknown: "Usage"
        }
    }
}

extension UsageWindow {
    /// Display label: a provider-specific `title` (model / proper noun) shown
    /// verbatim, otherwise the localized `kind` label. Shared by the menu-bar
    /// `ProviderRow` and the dashboard `ProviderUsageCard`.
    var labelText: Text {
        if let title { return Text(verbatim: title) }
        return Text(kind.label)
    }
}

/// UI presentation of a connection state. Lives here (SwiftUI layer), keeping the
/// model type (`ProviderConnection`) UI-framework-free.
extension ProviderConnection {
    var statusText: LocalizedStringKey {
        switch self {
        case .unknown: "Checking…"
        case .connected: "Connected"
        case .notInstalled: "Not installed"
        case .tokenExpired: "Token expired"
        case .endpointError: "Connection lost"
        case .noTrackableUsage: "No limit reported"
        }
    }

    var statusSymbol: String {
        switch self {
        case .unknown: "ellipsis.circle"
        case .connected: "checkmark.circle.fill"
        case .notInstalled: "minus.circle"
        case .tokenExpired: "exclamationmark.triangle.fill"
        case .endpointError: "xmark.octagon.fill"
        case .noTrackableUsage: "info.circle"
        }
    }

    var statusColor: Color {
        switch self {
        case .unknown: .secondary
        case .connected: .green
        case .notInstalled: .secondary
        case .tokenExpired: .orange
        case .endpointError: .red
        case .noTrackableUsage: .secondary
        }
    }
}

#if DEBUG
    #Preview("Providers — mixed states") {
        ProvidersView()
            .environment(
                AppState.preview([
                    .claude: ProviderRuntime(
                        connection: .connected,
                        windows: [
                            UsageWindow(
                                id: "five_hour", kind: .fiveHour, title: nil, used: 11, limit: 100,
                                resetsAt: .now.addingTimeInterval(14_280)),
                            UsageWindow(
                                id: "seven_day", kind: .weekly, title: nil, used: 27, limit: 100,
                                resetsAt: .now.addingTimeInterval(439_200)),
                            // Scoped (Phase 17): excluded from the menu-bar popover —
                            // only Session/Weekly (general) headline here.
                            UsageWindow(
                                id: "seven_day_model_Sonnet", kind: .weekly, title: "Sonnet",
                                used: 0, limit: 100, resetsAt: .now.addingTimeInterval(439_200),
                                scope: .model("Sonnet"), isActive: true),
                        ],
                        lastFetched: .now, errorMessage: nil, rawResponse: nil),
                    .codex: ProviderRuntime(
                        connection: .tokenExpired, windows: [], lastFetched: .now,
                        errorMessage: nil, rawResponse: nil),
                ])
            )
            .environment(AppPreferences())
            .frame(width: 320, height: 360)
    }
#endif
