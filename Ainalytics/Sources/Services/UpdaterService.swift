import Combine
import Sparkle
import SwiftUI

/// Wraps Sparkle's updater so the rest of the app can trigger and gate update
/// checks without importing Sparkle everywhere. Ainalytics ships `.dmg`-only
/// (App Sandbox off → no Mac App Store), so Sparkle — an EdDSA-signed appcast —
/// is the auto-update path. The feed URL and the public key live in Info.plist
/// (`SUFeedURL` / `SUPublicEDKey`); the matching private key signs each release
/// (`sign_update`) and never enters the app or the repo.
@MainActor @Observable
final class UpdaterService {
    @ObservationIgnored private let controller: SPUStandardUpdaterController

    /// `startingUpdater: false` is used by SwiftUI previews so a preview does not
    /// kick off a real scheduled update check.
    init(startingUpdater: Bool = true) {
        controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// The underlying Sparkle updater — passed to `CheckForUpdatesView`.
    var updater: SPUUpdater { controller.updater }

    /// Whether Sparkle checks on its own schedule. Sparkle persists this itself;
    /// the Settings toggle binds straight through.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}

/// The canonical Sparkle "Check for Updates…" control: a button that disables
/// itself while a check is already in flight (`canCheckForUpdates`). Used both in
/// the app menu (a `CommandGroup`) and the Settings → General "Updates" section.
struct CheckForUpdatesView: View {
    @State private var canCheckForUpdates = false
    private let updater: SPUUpdater

    init(updater: SPUUpdater) { self.updater = updater }

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!canCheckForUpdates)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheckForUpdates = $0 }
    }
}
