import OSLog
import Observation
import ServiceManagement

/// Launch-at-login control, backed by `SMAppService.mainApp`. The system is the
/// source of truth: `isEnabled` reflects the live registration status rather than
/// a duplicated preference, so it stays correct even when the user toggles the
/// login item from System Settings. No entitlement is needed for a Developer ID
/// (non-sandboxed) app registering its own login item (ARCHITECTURE §2 / §4a.ii).
@MainActor
@Observable
final class LoginItemService {
    /// True when the app is registered to launch at login.
    private(set) var isEnabled: Bool
    /// True when macOS is waiting for the user to approve the item in System Settings.
    private(set) var requiresApproval: Bool
    /// Last register/unregister error, surfaced in Settings (never a dead toggle).
    private(set) var lastError: String?

    @ObservationIgnored private let service = SMAppService.mainApp
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.beyazit.ainalytics", category: "loginitem")

    init() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    /// Re-read the system status — call when Settings appears, since the user may
    /// have changed the login item in System Settings since launch.
    func refresh() {
        isEnabled = service.status == .enabled
        requiresApproval = service.status == .requiresApproval
    }

    /// Register or unregister the login item, then re-read the status. Errors are
    /// captured into `lastError` for the UI rather than thrown.
    func setEnabled(_ enabled: Bool) async {
        lastError = nil
        do {
            if enabled {
                try service.register()
            } else {
                try await service.unregister()
            }
        } catch {
            lastError = error.localizedDescription
            logger.error(
                "Login item \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        refresh()
    }
}
