import AppKit
import SwiftUI

/// One provider's dashboard card: an accent header, a radial `Gauge` per limit
/// window, the renewal (longest-window reset) date, and the most-active model.
///
/// Degraded states (not installed / token expired / connection lost) render with
/// icon + text + colour, never colour alone (code-principles §7) — consistent
/// with the menu-bar `ProviderRow`.
struct ProviderUsageCard: View {
    @Environment(AppPreferences.self) private var preferences
    let id: ProviderID
    let runtime: ProviderRuntime
    /// The real, token-based most-used model from the Phase 5 log engine. When
    /// present it replaces the live-window proxy; `nil` falls back to the proxy
    /// (no logs yet, or a provider without token logs).
    var mostUsedModel: String? = nil

    private let gaugeColumns = [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .top)]

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header
                content
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProviderLogo(id: id)
            Text(id.displayName)
                .font(.headline)
            if let plan = PlanPriceCatalog.plan(for: id, key: preferences.selectedPlanKey(for: id)) {
                Text(verbatim: plan.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !runtime.connection.isConnected {
                ConnectionStatusChip(connection: runtime.connection)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if runtime.connection.isConnected && !runtime.windows.isEmpty {
            LazyVGrid(columns: gaugeColumns, alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(runtime.windows) { window in
                    gaugeCell(window)
                }
            }
            footer
        } else if runtime.connection == .tokenExpired {
            Text("Re-login in your CLI to reconnect.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// A single window: a radial capacity gauge (percent used) with the window
    /// label and a live reset countdown below.
    private func gaugeCell(_ window: UsageWindow) -> some View {
        VStack(spacing: 6) {
            Gauge(value: window.percentRemaining, in: 0...100) {
                EmptyView()
            } currentValueLabel: {
                Text(window.percentRemaining / 100, format: .percent.precision(.fractionLength(0)))
                    .font(.caption2)
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            // The gauge fills with what *remains* and the label reads the remaining
            // percent — matching the menu bar's bars; the severity tint still keys off
            // how much is *used*.
            .tint(Theme.usageTint(percentUsed: window.percentUsed, accent: Theme.accent(for: id)))

            window.labelText
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)

            if let resetsAt = window.resetsAt {
                ResetTimeFormatter.text(
                    for: resetsAt, style: preferences.resetDisplayStyle, phrasing: .bare
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.labelText)
        .accessibilityValue(
            Text(window.percentRemaining / 100, format: .percent.precision(.fractionLength(0))))
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let renewal = runtime.subscriptionWindow, let resetsAt = renewal.resetsAt {
                Label {
                    ResetTimeFormatter.text(
                        for: resetsAt, style: preferences.resetDisplayStyle, phrasing: .renew)
                } icon: {
                    Image(systemName: "calendar")
                }
            }
            if let mostUsedModel {
                modelLabel("Most used model", name: mostUsedModel)
            } else if let model = runtime.mostActiveModelWindow, let name = model.title {
                modelLabel("Most active model", name: name)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    /// A "<label>: <model name>" row. The model name is a proper noun shown
    /// verbatim (never localized).
    private func modelLabel(_ title: LocalizedStringKey, name: String) -> some View {
        Label {
            HStack(spacing: 4) {
                Text(title)
                Text(verbatim: name).fontWeight(.medium)
            }
        } icon: {
            Image(systemName: "cpu")
        }
    }
}

#if DEBUG
    #Preview("Provider cards") {
        ScrollView {
            VStack(spacing: 16) {
                ProviderUsageCard(id: .claude, runtime: PreviewData.mixedRuntimes[.claude]!)
                ProviderUsageCard(id: .codex, runtime: PreviewData.mixedRuntimes[.codex]!)
                ProviderUsageCard(
                    id: .codex,
                    runtime: ProviderRuntime(
                        connection: .tokenExpired, windows: [], lastFetched: .now,
                        errorMessage: nil, rawResponse: nil))
            }
            .padding()
        }
        .environment(AppPreferences())
        .frame(width: 360, height: 720)
    }
#endif
