import SwiftUI

/// The dashboard's "Model & surface limits" section (Phase 17): Claude's weekly
/// limits scoped to a specific model (Fable / Sonnet / Opus) or surface (Cowork).
///
/// A secondary detail beneath a provider card's main gauges — the plan-wide
/// Session / Weekly stay first-class above. Active limits show by default; inactive
/// ones appear only when the Settings toggle `showInactiveScopedLimits` is on. The
/// whole section renders nothing when there is nothing to show (so Codex, and Claude
/// with only general limits, never sprout an empty section).
struct ScopedLimitsView: View {
    @Environment(AppPreferences.self) private var preferences
    let id: ProviderID
    /// The provider's scoped windows (`runtime.scopedWindows`) — already filtered to
    /// non-general by the caller.
    let windows: [UsageWindow]

    /// What to display: always the active limits; inactive ones only when the user
    /// opted in. Sorted most-consumed first so the tightest limit reads at the top.
    private var visibleWindows: [UsageWindow] {
        windows
            .filter { $0.isActive || preferences.showInactiveScopedLimits }
            .sorted { $0.percentUsed > $1.percentUsed }
    }

    var body: some View {
        if !visibleWindows.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Divider()
                Text("Model & surface limits")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(visibleWindows) { window in
                    limitRow(window)
                }
            }
            .padding(.top, 2)
        }
    }

    /// One scoped limit: its model/surface label + percent remaining, a `UsageBar`,
    /// and a reset countdown. An inactive limit is dimmed AND tagged "Inactive" (text,
    /// not colour alone — code-principles §7).
    private func limitRow(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                window.labelText
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !window.isActive {
                    Text("Inactive")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(percentRemainingText(window)) left")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            UsageBar(percentUsed: window.percentUsed, accent: Theme.accent(for: id))
                .opacity(window.isActive ? 1 : 0.5)
            if let resetsAt = window.resetsAt {
                ResetTimeFormatter.text(
                    for: resetsAt, style: preferences.resetDisplayStyle, phrasing: .reset
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(window.labelText)
        .accessibilityValue(Text("\(percentRemainingText(window)) left"))
    }

    /// Locale-aware percent remaining (e.g. "72%"), matching the menu-bar rows so the
    /// "%@ left" localizable key is reused.
    private func percentRemainingText(_ window: UsageWindow) -> String {
        (window.percentRemaining / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}

#if DEBUG
    #Preview("Scoped limits") {
        ScopedLimitsView(
            id: .claude,
            windows: [
                UsageWindow(
                    id: "seven_day_model_Opus", kind: .weekly, title: "Opus", used: 88, limit: 100,
                    resetsAt: .now.addingTimeInterval(420_000), scope: .model("Opus"),
                    isActive: true),
                UsageWindow(
                    id: "seven_day_surface_Cowork", kind: .weekly, title: "Cowork", used: 34,
                    limit: 100, resetsAt: .now.addingTimeInterval(420_000),
                    scope: .surface("Cowork"), isActive: true),
                UsageWindow(
                    id: "seven_day_model_Fable", kind: .weekly, title: "Fable", used: 12,
                    limit: 100, resetsAt: .now.addingTimeInterval(420_000), scope: .model("Fable"),
                    isActive: false),
            ]
        )
        .padding()
        .frame(width: 320)
        .environment(AppPreferences())
    }
#endif
