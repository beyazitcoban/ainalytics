import AppKit

/// Drives the activation policy from window state. `MenuBarExtra` alone keeps the
/// app in `.accessory`, where an opened window floats over the previously-active
/// app and never owns the system menu bar (it kept showing e.g. "Terminal"). By
/// observing window key/close notifications we flip to `.regular` while a content
/// window — the dashboard or the Settings window — is open, so the menu shows
/// "Ainalytics" with the standard window menus, then drop back to the menu-bar
/// agent policy when the last one closes. The "Show dock icon" preference still
/// governs the idle (no-window) state. The actual policy decision lives in
/// `AppPreferences.syncActivationPolicy()` (single source of truth).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                // Defer to the next main-actor tick so a closing window has turned
                // invisible before the policy is recomputed (willClose fires while
                // the window is still in `NSApp.windows`).
                Task { @MainActor in AppPreferences.syncActivationPolicy() }
            }
        }
        AppPreferences.syncActivationPolicy()
    }
}
