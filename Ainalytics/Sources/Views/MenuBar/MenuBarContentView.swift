import AppKit
import SwiftUI

/// Menu-bar popover content: per-provider usage + reset countdowns, a manual
/// refresh, and the "Updated …" stamp. The poller's lifecycle starts here (the
/// menu bar is the always-present scene).
///
/// Tahoe-native Liquid Glass: the popover material is already glass, so the chrome
/// stays restrained — real `.glassEffect`/glass button styles are reserved for the
/// floating affordances (refresh + the footer action cluster), while content sits
/// on the popover material on a shared spacing rhythm.
struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppState.self) private var appState
    @Environment(UsagePoller.self) private var poller

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            ProvidersView()

            if let updated = appState.lastUpdated {
                updatedStamp(updated)
            }

            footer
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("Ainalytics")
                .font(.title3.weight(.semibold))
            Spacer()
            // Quit lives in the title corner (Refresh moved to the footer cluster) —
            // a low-frequency action kept out of the way of the primary controls.
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.glass)
            .help("Quit Ainalytics")
            .accessibilityLabel("Quit Ainalytics")
        }
    }

    private func updatedStamp(_ updated: Date) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text("Updated")
            Text(updated, style: .relative)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    /// The floating action cluster — a prominent "Open Dashboard" alongside icon-only
    /// Settings and Refresh, all on one row, grouped in a `GlassEffectContainer` so the
    /// glass pieces blend.
    private var footer: some View {
        GlassEffectContainer(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    openWindow(id: "dashboard")
                    Self.activateApp()
                } label: {
                    Label("Open Dashboard", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .simultaneousGesture(TapGesture().onEnded { Self.activateApp() })
                .buttonStyle(.glass)
                .help("Settings…")
                .accessibilityLabel("Settings…")

                Button {
                    Task { await poller.refreshNow() }
                } label: {
                    if poller.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.glass)
                .disabled(poller.isRefreshing)
                .help("Refresh now")
                .accessibilityLabel("Refresh now")
            }
            .controlSize(.large)
        }
    }

    /// Brings the app and its just-opened window to the front. A menu-bar agent in
    /// `.accessory` activation policy (dock icon hidden) otherwise opens windows
    /// *behind* the active app. Deferred one runloop tick so it fires after the
    /// window exists.
    private static func activateApp() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
