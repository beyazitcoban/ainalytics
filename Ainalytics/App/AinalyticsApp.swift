import SwiftData
import SwiftUI

/// Ainalytics — application entry point.
///
/// Scene composition reflects the kurgulama Phase F.1b decision:
/// **MenuBarExtra** (at-a-glance limits + notifications) + a **Dashboard Window**
/// (heatmap, charts, cost) + a **Settings** scene (⌘,).
///
/// The app ships as a menu-bar-primary agent (`LSUIElement = true`); the
/// "Show dock icon" preference flips the activation policy at runtime.
@main
struct AinalyticsApp: App {
    // Owns the window-driven activation policy (menu-bar agent ⇄ regular app) so an
    // open dashboard/Settings window owns the system menu bar.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var appState: AppState
    @State private var preferences: AppPreferences
    @State private var poller: UsagePoller
    @State private var notificationService: NotificationService
    @State private var logActivity: LogActivityState
    @State private var loginItem: LoginItemService
    @State private var updater: UpdaterService

    init() {
        let appState = AppState()
        let preferences = AppPreferences()
        let notificationService = NotificationService()
        let poller = UsagePoller(
            appState: appState,
            preferences: preferences,
            modelContext: AppContainer.shared.mainContext,
            notificationService: notificationService)
        _appState = State(initialValue: appState)
        _preferences = State(initialValue: preferences)
        _notificationService = State(initialValue: notificationService)
        _poller = State(initialValue: poller)
        _logActivity = State(initialValue: LogActivityState())
        _loginItem = State(initialValue: LoginItemService())
        _updater = State(initialValue: UpdaterService())
        // Start polling at launch — MenuBarExtra(.window) renders its content
        // lazily (first popover open), so a view `.task` would delay the first
        // refresh until the user clicks the menu bar. start() is idempotent.
        poller.start()
        // Ask for notification permission once (Phase 3); no-op if already decided.
        Task { await notificationService.requestAuthorizationIfNeeded() }
    }

    var body: some Scene {
        // Menu bar — always present, drives the at-a-glance view + notifications.
        // One MenuBarExtra with a custom `label:` — SceneBuilder can't branch between two
        // MenuBarExtra types, so the label itself shows the pinned provider's usage or the
        // app glyph. (The Phase 11 "blob" was the 360-pt asset intrinsic size, now 16 pt —
        // not the custom label.)
        MenuBarExtra {
            menuBarContent
        } label: {
            menuBarItemLabel
                .accessibilityLabel("Ainalytics")
        }
        .menuBarExtraStyle(.window)
        .modelContainer(AppContainer.shared)

        // Dashboard — the rich visualization surface, opened from the menu bar.
        Window("Ainalytics", id: "dashboard") {
            RootView()
                // Fixed width, vertically resizable — the System Settings model. The
                // dashboard holds precise charts/heatmaps whose layout is sensitive to
                // width, so the horizontal axis is locked (min = ideal = max) while the
                // height stays free above a floor. `.windowResizability(.contentSize)`
                // makes the window adopt exactly this frame's resize range.
                .frame(
                    minWidth: 920, idealWidth: 920, maxWidth: 920,
                    minHeight: 560, idealHeight: 640, maxHeight: .infinity
                )
                .environment(appState)
                .environment(preferences)
                .environment(poller)
                .environment(logActivity)
        }
        .windowResizability(.contentSize)
        .modelContainer(AppContainer.shared)
        .commands {
            // Standard "Check for Updates…" in the app menu, just after "About".
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater.updater)
            }
        }

        // Settings (⌘,).
        Settings {
            SettingsView()
                .environment(appState)
                .environment(preferences)
                .environment(poller)
                .environment(notificationService)
                .environment(loginItem)
                .environment(updater)
        }
    }

    /// The menu-bar item's label: with a provider pinned (Settings → General → Menu Bar)
    /// it shows that provider's live usage (logo and/or remaining %, per the chosen
    /// `MenuBarStyle`); with no pin it shows the app's own glyph. Reading `preferences` /
    /// `appState` here keeps it live — a selection or a usage refresh re-renders the scene.
    ///
    /// The custom-label path under `.menuBarExtraStyle(.window)` was avoided after the
    /// Phase 11 menu-bar "blob"; the real cause was the 360-pt asset intrinsic size (now
    /// 16 pt), not the label itself.
    @ViewBuilder private var menuBarItemLabel: some View {
        if let pinned = preferences.menuBarProvider {
            MenuBarLabel(
                provider: pinned,
                runtime: appState.runtime(for: pinned),
                style: preferences.menuBarStyle)
        } else {
            Image("ainalytics-mono")
        }
    }

    /// The shared popover content.
    private var menuBarContent: some View {
        MenuBarContentView()
            .environment(appState)
            .environment(preferences)
            .environment(poller)
    }
}
