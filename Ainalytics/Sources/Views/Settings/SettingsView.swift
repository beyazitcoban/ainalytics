import AppKit
import SwiftUI

/// Settings window. A "General" tab (app behaviour + language), a "Providers" tab
/// (which providers to track), a "Notifications" tab, and — in DEBUG only — a
/// "Developer" tab showing the raw-data verifiability view. Tabs are shown flat
/// (no nested NavigationStack) because a pushed navigation inside a Settings tab
/// renders a stray back button on macOS.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ProviderSettingsView()
                .tabItem { Label("Providers", systemImage: "square.stack.3d.up") }
            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
            #if DEBUG
                DebugDataView()
                    .tabItem { Label("Developer", systemImage: "hammer") }
            #endif
        }
        .frame(width: 540, height: 420)
        // Opaque window background (the standard System-Settings look). The windows
        // are otherwise translucent (wallpaper-tinted), which made the grouped-form
        // section fills and the tab-selection highlight render inconsistently; a
        // solid base settles both. Dashboard / menu-bar translucency is untouched.
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The General settings form — app behaviour, the menu-bar provider/style, and
/// language. Hosted by the ⌘, Settings window's "General" tab.
private struct GeneralSettingsView: View {
    @Environment(AppPreferences.self) private var prefs
    @Environment(LoginItemService.self) private var loginItem
    @Environment(UpdaterService.self) private var updater

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                Toggle("Show dock icon", isOn: $prefs.showDockIcon)
                Toggle("Launch at login", isOn: loginItemBinding)
                if loginItem.requiresApproval {
                    Text("Approve Ainalytics in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = loginItem.lastError {
                    Text(verbatim: error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Picker("Refresh every", selection: $prefs.refreshIntervalMinutes) {
                    ForEach(AppPreferences.selectableRefreshIntervals, id: \.self) { minutes in
                        Text(Self.intervalLabel(minutes)).tag(minutes)
                    }
                }
                Picker("Reset display", selection: $prefs.resetDisplayStyle) {
                    ForEach(ResetDisplayStyle.allCases) { style in
                        Text(style.pickerLabel).tag(style)
                    }
                }
                Toggle(
                    "Show inactive model & surface limits",
                    isOn: $prefs.showInactiveScopedLimits)
            } header: {
                Text("General")
            }

            Section {
                Picker("Menu bar shows", selection: menuBarBinding) {
                    Text("App icon").tag(Optional<ProviderID>.none)
                    ForEach(prefs.enabledProviderIDs, id: \.self) { id in
                        Text(verbatim: id.displayName).tag(Optional(id))
                    }
                }
                Picker("Menu bar style", selection: $prefs.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.pickerLabel).tag(style)
                    }
                }
                .disabled(prefs.menuBarProvider == nil)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("Show one provider's live usage right in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Language", selection: $prefs.languageCode) {
                    Text("System").tag("")
                    Text(verbatim: "Türkçe").tag("tr")
                    Text(verbatim: "English (US)").tag("en-US")
                    Text(verbatim: "English (UK)").tag("en-GB")
                    Text(verbatim: "Deutsch").tag("de")
                    Text(verbatim: "Español").tag("es")
                }
                Button("Relaunch to apply language") { Self.relaunch() }
            } header: {
                Text("Language")
            } footer: {
                Text("Language changes apply on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Automatically check for updates", isOn: automaticUpdatesBinding)
                CheckForUpdatesView(updater: updater.updater)
            } header: {
                Text("Updates")
            } footer: {
                Text(Self.versionFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }

    /// Binds the menu-bar provider-mode selection (a `ProviderID?`) to the stored
    /// raw-id preference. `nil` → the menu bar shows the app's generic glyph.
    private var menuBarBinding: Binding<ProviderID?> {
        Binding(
            get: { prefs.menuBarProvider },
            set: { prefs.setMenuBarProvider($0) })
    }

    /// Toggle bound to the live login-item status; flipping it (un)registers the
    /// item off the main-thread-blocking path via a Task.
    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { newValue in Task { await loginItem.setEnabled(newValue) } })
    }

    /// Binds Sparkle's "check automatically" preference (Sparkle persists it).
    private var automaticUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 })
    }

    /// "Version 1.0.0 (100)" from the bundle, shown under the Updates section.
    private static var versionFooter: String {
        let short =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let version = "\(short) (\(build))"
        return String(localized: "Version \(version)")
    }

    /// Localized cadence label ("5 minutes", "1 hour") via Foundation's units style.
    private static func intervalLabel(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    /// Quit and relaunch so a language change applies immediately (macOS resolves
    /// the bundle language at launch — it cannot be hot-swapped while running).
    private static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.4; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
        .environment(AppPreferences())
        .environment(NotificationService())
        .environment(LoginItemService())
        .environment(UpdaterService(startingUpdater: false))
}
