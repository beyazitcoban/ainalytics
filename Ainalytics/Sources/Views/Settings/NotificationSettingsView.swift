import AppKit
import SwiftUI
import UserNotifications

/// Notification preferences (Phase 3): a master switch, per-threshold warning
/// toggles, a limit-reset toggle, and per-provider muting. When the system has
/// notifications turned off, an inline hint deep-links to System Settings rather
/// than leaving a dead toggle (code-principles §1 — graceful denied state).
///
/// Built from Apple-native `Form` primitives only — no new component (Rule #7).
struct NotificationSettingsView: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(NotificationService.self) private var notifications

    var body: some View {
        @Bindable var prefs = prefs

        Form {
            Section {
                Toggle("Enable notifications", isOn: $prefs.notificationsEnabled)
            } footer: {
                authorizationHint
            }

            Section {
                ForEach(AppPreferences.selectableThresholds, id: \.self) { threshold in
                    Toggle(thresholdLabel(threshold), isOn: thresholdBinding(threshold))
                }
            } header: {
                Text("Usage thresholds")
            } footer: {
                Text("Get notified once when usage crosses a threshold, and again when it resets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!prefs.notificationsEnabled)

            Section {
                Toggle("Limit reset alerts", isOn: $prefs.resetNotificationsEnabled)
            }
            .disabled(!prefs.notificationsEnabled)

            Section {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    Toggle(isOn: providerBinding(id)) {
                        Text(id.displayName)
                    }
                }
            } header: {
                Text("Providers")
            }
            .disabled(!prefs.notificationsEnabled)
        }
        .formStyle(.grouped)
        .task { await notifications.refreshAuthorizationStatus() }
    }

    /// Shown only when the system denies notifications — a warning plus a deep link.
    @ViewBuilder private var authorizationHint: some View {
        if notifications.authorizationStatus == .denied {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "Notifications are turned off in System Settings.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                Button("Open System Settings") { openNotificationSettings() }
            }
            .font(.caption)
        }
    }

    /// A locale-aware percent label for a threshold (e.g. "80%").
    private func thresholdLabel(_ threshold: Int) -> String {
        (Double(threshold) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// Binding over membership in the active-thresholds set.
    private func thresholdBinding(_ threshold: Int) -> Binding<Bool> {
        Binding(
            get: { prefs.enabledThresholds.contains(threshold) },
            set: { isOn in
                if isOn {
                    prefs.enabledThresholds.insert(threshold)
                } else {
                    prefs.enabledThresholds.remove(threshold)
                }
            })
    }

    /// Binding over a provider being *unmuted* (toggle on = notify for this provider).
    private func providerBinding(_ id: ProviderID) -> Binding<Bool> {
        Binding(
            get: { !prefs.mutedProviderIDs.contains(id.rawValue) },
            set: { isEnabled in
                if isEnabled {
                    prefs.mutedProviderIDs.remove(id.rawValue)
                } else {
                    prefs.mutedProviderIDs.insert(id.rawValue)
                }
            })
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    NotificationSettingsView()
        .environment(AppPreferences())
        .environment(NotificationService())
        .frame(width: 540, height: 400)
}
