import AppKit
import Foundation
import OSLog
import Observation
import SwiftData
import WidgetKit

/// Owns *when* usage is refreshed: an interval loop (default 5 min, from
/// `AppPreferences`), a refresh on system wake, and manual "refresh now". The
/// *what* (fetching, parsing, persistence) lives in `AppState.refreshAll` — this
/// type only schedules (ARCHITECTURE §2, UsagePoller module).
@MainActor
@Observable
final class UsagePoller {
    /// Why a given refresh ran — surfaced in the persisted poller log so the cadence
    /// (and any App-Nap / sleep gap) is reconstructable after the fact (#01).
    enum RefreshReason: String {
        case initial  // first run at start()
        case loop  // the interval timer fired
        case wake  // system woke from sleep
        case manual  // user tapped "refresh now"
    }

    /// True while a refresh is in flight — drives the menu-bar button's disabled state.
    private(set) var isRefreshing = false

    @ObservationIgnored private let appState: AppState
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let notificationService: NotificationService?
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    /// Wall-clock of the last refresh, to log the real elapsed gap between ticks —
    /// a gap ≫ the interval while awake is the App-Nap throttling signature (#01).
    @ObservationIgnored private var lastRefreshAt: Date?
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.beyazit.ainalytics", category: "poller")

    init(
        appState: AppState,
        preferences: AppPreferences,
        modelContext: ModelContext,
        notificationService: NotificationService? = nil
    ) {
        self.appState = appState
        self.preferences = preferences
        self.modelContext = modelContext
        self.notificationService = notificationService
    }

    /// Begin the refresh lifecycle: an immediate refresh, then the interval loop
    /// plus the wake observer. Idempotent — safe to call from `.task`.
    func start() {
        guard loopTask == nil else { return }
        observeWake()
        loopTask = Task { [weak self] in
            var firstTick = true
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshNow(reason: firstTick ? .initial : .loop)
                firstTick = false
                let minutes = max(1, self.preferences.refreshIntervalMinutes)
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    /// On-demand refresh (interval loop, on-wake, manual button). Coalesces
    /// concurrent calls. `reason` defaults to `.manual` so the view call sites are
    /// unchanged; the loop and wake observer pass their own reason.
    func refreshNow(reason: RefreshReason = .manual) async {
        // Instrument the cadence before the coalescing guard so a skipped (already
        // in-flight) refresh is still visible, and the elapsed gap exposes throttling.
        let now = Date.now
        let elapsed = lastRefreshAt.map { now.timeIntervalSince($0) }
        let scheduled = max(1, preferences.refreshIntervalMinutes) * 60
        logger.notice(
            """
            refresh reason=\(reason.rawValue, privacy: .public) \
            sinceLast=\(elapsed.map { String(format: "%.0fs", $0) } ?? "—", privacy: .public) \
            interval=\(scheduled, privacy: .public)s \
            inFlight=\(self.isRefreshing, privacy: .public)
            """)
        lastRefreshAt = now

        guard !isRefreshing else { return }
        isRefreshing = true
        await appState.refreshAll(
            persistTo: modelContext, enabled: Set(preferences.enabledProviderIDs))
        // React to the fresh readings: threshold + reset notifications (Phase 3).
        notificationService?.evaluate(runtimes: appState.runtimes, preferences: preferences)
        // Publish a token-free snapshot for the widget, then nudge it to reload (Phase 12).
        SharedSnapshotStore.write(appState.sharedSnapshot(pinned: preferences.menuBarProvider))
        WidgetCenter.shared.reloadAllTimelines()
        isRefreshing = false
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.logger.notice("system wake → on-wake refresh")
                await self?.refreshNow(reason: .wake)
            }
        }
    }

    deinit {
        loopTask?.cancel()
    }
}
