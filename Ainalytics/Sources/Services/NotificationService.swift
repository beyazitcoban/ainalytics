import Foundation
import OSLog
import UserNotifications

/// Turns each usage refresh into notifications: one-shot threshold warnings
/// (re-armed on recovery) and limit-reset alerts.
///
/// The *decision* — which notifications a refresh warrants — is the pure,
/// side-effect-free `plan(...)`, so it is unit-testable without the system
/// notification center. This class only: requests authorization, posts what the
/// planner decided, and persists the per-window "armed" memory across launches.
///
/// ARCHITECTURE §2: consumes `UsagePoller` output. It reads usage numbers only —
/// never a token (tokens never reach this layer).
@MainActor
@Observable
final class NotificationService {
    /// Current system authorization. Drives the Settings "turned off" hint.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private let center: UNUserNotificationCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.beyazit.ainalytics", category: "notifications")

    /// Per-window memory: the highest threshold already alerted (so each crossing
    /// fires once), plus the last reset date and percent seen (to detect a rollover).
    /// Persisted to `UserDefaults` so a relaunch never re-spams already-fired levels.
    @ObservationIgnored private var armed: [String: ArmRecord]

    init(center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
        self.armed = Self.loadArmed(from: defaults)
    }

    // MARK: - Authorization

    /// Request notification permission once. Safe to call every launch — the system
    /// only shows the prompt when the status is `.notDetermined`.
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            authorizationStatus = granted ? .authorized : .denied
        } catch {
            logger.error(
                "Notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-read the live authorization (e.g. when the Settings tab appears) so a change
    /// made in System Settings is reflected without relaunching.
    func refreshAuthorizationStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    // MARK: - Evaluation

    /// Called after every refresh: plan from the new runtimes, persist the updated
    /// armed memory, and post the planned notifications (only when authorized).
    ///
    /// The armed memory updates even when posting is suppressed (not authorized),
    /// so granting permission later does not retroactively fire for old crossings.
    func evaluate(runtimes: [ProviderID: ProviderRuntime], preferences: AppPreferences) {
        guard preferences.notificationsEnabled else { return }

        let outcome = Self.plan(
            now: .now,
            runtimes: runtimes,
            thresholds: preferences.enabledThresholds,
            resetEnabled: preferences.resetNotificationsEnabled,
            mutedProviders: preferences.mutedProviderIDs,
            armed: armed)

        armed = outcome.armed
        Self.saveArmed(outcome.armed, to: defaults)

        // Persisted instrumentation (#01): what the planner decided this refresh, at
        // `.notice` so it survives on disk to the next reset window for `log show`.
        for line in outcome.logEvents { logger.notice("\(line, privacy: .public)") }

        // Scheduling is authorization-independent: the request is registered now and
        // the system gates *delivery* on authorization (often granted after first
        // launch). It is re-issued every refresh (same id replaces), so it still
        // takes hold once permission lands. Immediate posts stay authorization-gated,
        // with the armed memory already advanced so a late grant never replays.
        for scheduled in outcome.scheduledResets { schedule(scheduled) }
        if !outcome.cancelledIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: outcome.cancelledIdentifiers)
        }

        guard authorizationStatus == .authorized else { return }
        for note in outcome.notifications { post(note) }
    }

    private func post(_ note: PlannedNotification) {
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        content.sound = .default
        // `trigger: nil` delivers immediately.
        let request = UNNotificationRequest(
            identifier: note.identifier, content: content, trigger: nil)
        center.add(request)
        logger.notice("Posted notification \(note.identifier, privacy: .public)")
    }

    /// Schedule a reset alert at a known future instant (the window's `resets_at`).
    /// A calendar trigger lets the system deliver it even if the poller never runs
    /// at that moment (sleep / App Nap) — this is the #01 fix. Re-adding the same
    /// identifier replaces the pending request, so a shifted `resets_at` reschedules.
    private func schedule(_ scheduled: ScheduledReset) {
        let content = UNMutableNotificationContent()
        content.title = scheduled.notification.title
        content.body = scheduled.notification.body
        content.sound = .default
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: scheduled.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: scheduled.notification.identifier, content: content, trigger: trigger)
        center.add(request)
        logger.notice(
            "Scheduled reset \(scheduled.notification.identifier, privacy: .public)")
    }

    // MARK: - Pure planner (unit-testable; no system API, no side effects)

    /// What a single refresh decided: the notifications to post and the new armed
    /// memory to persist. Deterministic given its inputs.
    struct PlanOutcome: Equatable {
        /// Post immediately: threshold crossings + the early-reset backstop.
        let notifications: [PlannedNotification]
        /// (Re)schedule at the window's known `resets_at` instant.
        let scheduledResets: [ScheduledReset]
        /// Pending scheduled identifiers to cancel (reset turned off / window gone).
        let cancelledIdentifiers: [String]
        let armed: [String: ArmRecord]
        /// Human-readable diagnostics the caller logs at `.notice` (persisted, #01).
        let logEvents: [String]
    }

    /// Decide what a refresh warrants: immediate notifications, reset alerts to
    /// schedule ahead, pending alerts to cancel, and the new armed memory. Pure and
    /// deterministic given `now` — no `Date.now`, no system calls (unit-testable).
    ///
    /// Threshold ladder: `currentLevel` is the highest active threshold at or below
    /// the window's percent-used. A crossing up from the armed level fires once;
    /// a drop below it (recovery, e.g. after a reset) re-arms silently.
    ///
    /// Reset alerts are primarily **scheduled ahead** at the window's known
    /// `resets_at`, so delivery never depends on a poll landing near the reset
    /// instant (the #01 fix — sleep / App Nap no longer delay it). The two-signal
    /// detection (reset instant jumps forward past `resetForwardTolerance` **and**
    /// usage drops by `resetUsageDropMargin`) stays as a **backstop**: it posts an
    /// immediate alert only for an *early* rollover — when the scheduled instant
    /// (`oldReset`) is still in the future at `now`, so the scheduled alert has not
    /// fired yet. A normal, on-time rollover is left to the scheduled alert, which
    /// avoids a double-fire. Scheduled and backstop use distinct identifiers.
    static func plan(
        now: Date,
        runtimes: [ProviderID: ProviderRuntime],
        thresholds: Set<Int>,
        resetEnabled: Bool,
        mutedProviders: Set<String>,
        armed: [String: ArmRecord]
    ) -> PlanOutcome {
        var newArmed = armed
        var notifications: [PlannedNotification] = []
        var scheduledResets: [ScheduledReset] = []
        var cancelledIdentifiers: [String] = []
        var logEvents: [String] = []
        let sortedThresholds = thresholds.sorted()

        for id in ProviderID.allCases {
            guard let runtime = runtimes[id], runtime.connection.isConnected else { continue }
            let muted = mutedProviders.contains(id.rawValue)

            for window in runtime.windows {
                let key = "\(id.rawValue)|\(window.id)"
                let pct = window.percentUsed
                let windowLabel = label(for: window)
                let resetIdentifier = "\(id.rawValue).\(window.id).reset"
                let backstopIdentifier = "\(id.rawValue).\(window.id).reset.late"
                var record =
                    newArmed[key]
                    ?? ArmRecord(
                        notifiedLevel: 0, lastResetAt: window.resetsAt, lastPercentUsed: pct,
                        scheduledResetAt: nil)

                // --- Reset detection (backstop only): window rolled over (forward
                // jump + usage drop). The scheduled alert handles the normal case;
                // an immediate alert fires ONLY for an early rollover (oldReset still
                // in the future at `now`, so the scheduled alert has not fired yet).
                if let newReset = window.resetsAt, let oldReset = record.lastResetAt {
                    let rolledOver = newReset > oldReset.addingTimeInterval(resetForwardTolerance)
                    let usageDropped = pct <= record.lastPercentUsed - resetUsageDropMargin
                    if rolledOver && usageDropped {
                        if resetEnabled && !muted && oldReset > now {
                            notifications.append(
                                PlannedNotification(
                                    providerName: id.displayName, windowLabel: windowLabel,
                                    identifier: backstopIdentifier, event: .reset))
                            logEvents.append(
                                "backstop reset \(key): early rollover at \(now) "
                                    + "(scheduled instant \(oldReset) not yet fired) → posting now")
                        }
                        record.notifiedLevel = 0  // a reset re-arms the threshold ladder
                    }
                }
                if let newReset = window.resetsAt { record.lastResetAt = newReset }

                // --- Scheduled reset reconciliation: keep a pending alert at the
                // known future reset instant. Reschedule when `resets_at` shifts
                // (Anthropic's early/late reset), cancel when it can no longer apply.
                let target: Date? =
                    (resetEnabled && !muted) ? window.resetsAt.flatMap { $0 > now ? $0 : nil } : nil
                if let target {
                    // Always (re)issue — idempotent (the same id replaces a pending
                    // request). Re-adding every refresh keeps it robust to notification
                    // authorization granted AFTER launch; only the change is logged so
                    // the per-poll re-issue does not flood the log.
                    scheduledResets.append(
                        ScheduledReset(
                            notification: PlannedNotification(
                                providerName: id.displayName, windowLabel: windowLabel,
                                identifier: resetIdentifier, event: .reset),
                            fireDate: target))
                    if record.scheduledResetAt != target {
                        logEvents.append(
                            "schedule reset \(key) at \(target)"
                                + (record.scheduledResetAt == nil ? "" : " (rescheduled)"))
                    }
                } else if record.scheduledResetAt != nil {
                    cancelledIdentifiers.append(resetIdentifier)
                    logEvents.append("cancel scheduled reset \(key)")
                }
                record.scheduledResetAt = target

                // --- Threshold ladder.
                let currentLevel = sortedThresholds.last(where: { Double($0) <= pct }) ?? 0
                if currentLevel > record.notifiedLevel {
                    if !muted {
                        notifications.append(
                            PlannedNotification(
                                providerName: id.displayName, windowLabel: windowLabel,
                                identifier: "\(id.rawValue).\(window.id).threshold.\(currentLevel)",
                                event: .threshold(currentLevel)))
                    }
                    record.notifiedLevel = currentLevel
                } else if currentLevel < record.notifiedLevel {
                    record.notifiedLevel = currentLevel  // recovery → re-arm, no alert
                }

                record.lastPercentUsed = pct
                newArmed[key] = record
            }
        }

        return PlanOutcome(
            notifications: notifications, scheduledResets: scheduledResets,
            cancelledIdentifiers: cancelledIdentifiers, armed: newArmed, logEvents: logEvents)
    }

    /// A reset instant must jump at least this far forward to count as a rollover.
    /// Real windows reset on a fixed boundary (hours/days away); this filters clock
    /// skew and minor provider re-computation between refreshes.
    static let resetForwardTolerance: TimeInterval = 60

    /// Usage must drop by at least this many percent for a forward reset jump to be
    /// confirmed as a real rollover (a reset empties the window).
    static let resetUsageDropMargin: Double = 5

    /// A window's display label for notification copy: a provider-specific `title`
    /// (proper noun / model name) verbatim, otherwise the localized `kind` label.
    /// Reuses the existing String Catalog keys (Session / Weekly / Monthly / Usage).
    private static func label(for window: UsageWindow) -> String {
        if let title = window.title { return title }
        switch window.kind {
        case .fiveHour: return String(localized: "Session")
        case .weekly: return String(localized: "Weekly")
        case .monthly: return String(localized: "Monthly")
        case .unknown: return String(localized: "Usage")
        }
    }

    // MARK: - Armed-state persistence

    private static let armedKey = "notif.armed.v1"

    private static func loadArmed(from defaults: UserDefaults) -> [String: ArmRecord] {
        guard let data = defaults.data(forKey: armedKey),
            let decoded = try? JSONDecoder().decode([String: ArmRecord].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func saveArmed(_ armed: [String: ArmRecord], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(armed) else { return }
        defaults.set(data, forKey: armedKey)
    }
}

/// Per-window notification memory. `Codable` for `UserDefaults` JSON persistence.
struct ArmRecord: Codable, Equatable {
    /// Highest threshold already alerted for this window (0 = none armed).
    var notifiedLevel: Int
    /// The reset instant last observed (to detect a forward rollover).
    var lastResetAt: Date?
    /// The percent-used last observed (to confirm a reset emptied the window).
    var lastPercentUsed: Double
    /// The `resets_at` we last scheduled a pending alert for, so a shift reschedules
    /// and a no-longer-valid window cancels. Optional → records persisted before the
    /// #01 fix decode with this `nil` (backward compatible).
    var scheduledResetAt: Date?
}

/// A reset alert to (re)schedule at a known future instant (the window's
/// `resets_at`). Carries a `PlannedNotification` so copy/localization stays in one
/// place; `evaluate` turns it into a calendar-triggered request.
struct ScheduledReset: Equatable {
    let notification: PlannedNotification
    let fireDate: Date
}

/// A notification the planner decided to post. Carries semantic fields; the copy is
/// composed (and localized) in `title` / `body` so the planner stays text-agnostic.
struct PlannedNotification: Equatable {
    enum Event: Equatable {
        case threshold(Int)  // crossed this usage percent
        case reset  // window rolled over
    }

    let providerName: String  // verbatim brand name (e.g. "Claude") — not localized
    let windowLabel: String  // resolved window label (verbatim title or localized kind)
    let identifier: String
    let event: Event

    /// The notification title is the provider's brand name, shown verbatim.
    var title: String { providerName }

    var body: String {
        switch event {
        case .threshold(let level):
            let pct = (Double(level) / 100).formatted(.percent.precision(.fractionLength(0)))
            return String(format: String(localized: "%1$@ is %2$@ used."), windowLabel, pct)
        case .reset:
            return String(format: String(localized: "Your %@ limit has reset."), windowLabel)
        }
    }
}
