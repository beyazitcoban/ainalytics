import Foundation
import Testing

@testable import Ainalytics

/// Unit tests for the pure notification planner (`NotificationService.plan`).
/// This is the risky logic — the threshold ladder (fire-once + re-arm) and the
/// reset handling — verified without the system notification center.
///
/// Reset handling (#01) has two paths the tests pin down:
/// - **Scheduled-ahead** (primary): a future `resets_at` produces a `ScheduledReset`
///   the caller hands to the system; delivery no longer depends on a poll landing
///   near the reset instant.
/// - **Backstop** (immediate): the two-signal detection posts an alert ONLY for an
///   *early* rollover (the scheduled instant `oldReset` is still in the future at
///   `now`, so the scheduled alert has not fired yet). A normal, on-time rollover is
///   left to the scheduled alert — no double-fire.
///
/// `@MainActor` because `plan` is a static member of a `@MainActor` type.
@MainActor
struct NotificationPlannerTests {

    // MARK: Fixtures

    /// A fixed "now" for the threshold tests (reset-agnostic — their windows carry
    /// no `resets_at`). Reset tests build their instants relative to `base`.
    private let now = Date(timeIntervalSince1970: 1_000_000_000)
    private let base = Date(timeIntervalSince1970: 1_000_000_000)

    private func window(
        id: String = "w", kind: UsageWindowKind = .fiveHour, used: Double, resetsAt: Date? = nil
    ) -> UsageWindow {
        UsageWindow(id: id, kind: kind, title: nil, used: used, limit: 100, resetsAt: resetsAt)
    }

    private func connected(_ windows: [UsageWindow]) -> ProviderRuntime {
        ProviderRuntime(
            connection: .connected, windows: windows, lastFetched: nil, errorMessage: nil,
            rawResponse: nil)
    }

    // MARK: Threshold ladder

    @Test func thresholdFiresOnceThenStaysSilent() {
        let runtimes: [ProviderID: ProviderRuntime] = [.claude: connected([window(used: 82)])]
        let first = NotificationService.plan(
            now: now, runtimes: runtimes, thresholds: [80, 95], resetEnabled: true,
            mutedProviders: [], armed: [:])
        #expect(first.notifications.count == 1)
        #expect(first.notifications.first?.event == .threshold(80))

        // Same reading carried with the armed state → no repeat (do not spam).
        let second = NotificationService.plan(
            now: now, runtimes: runtimes, thresholds: [80, 95], resetEnabled: true,
            mutedProviders: [], armed: first.armed)
        #expect(second.notifications.isEmpty)
    }

    @Test func thresholdLadderClimbsToNextLevel() {
        let low: [ProviderID: ProviderRuntime] = [.claude: connected([window(used: 82)])]
        let s1 = NotificationService.plan(
            now: now, runtimes: low, thresholds: [80, 95], resetEnabled: true, mutedProviders: [],
            armed: [:])
        #expect(s1.notifications.first?.event == .threshold(80))

        let high: [ProviderID: ProviderRuntime] = [.claude: connected([window(used: 96)])]
        let s2 = NotificationService.plan(
            now: now, runtimes: high, thresholds: [80, 95], resetEnabled: true, mutedProviders: [],
            armed: s1.armed)
        #expect(s2.notifications.count == 1)
        #expect(s2.notifications.first?.event == .threshold(95))
    }

    @Test func recoveryReArmsThreshold() {
        let high: [ProviderID: ProviderRuntime] = [.claude: connected([window(used: 85)])]
        let s1 = NotificationService.plan(
            now: now, runtimes: high, thresholds: [80, 95], resetEnabled: true, mutedProviders: [],
            armed: [:])
        #expect(s1.notifications.count == 1)

        // Drop below the armed level → silent re-arm.
        let low: [ProviderID: ProviderRuntime] = [.claude: connected([window(used: 50)])]
        let s2 = NotificationService.plan(
            now: now, runtimes: low, thresholds: [80, 95], resetEnabled: true, mutedProviders: [],
            armed: s1.armed)
        #expect(s2.notifications.isEmpty)

        // Climb back above the threshold → fires again.
        let s3 = NotificationService.plan(
            now: now, runtimes: high, thresholds: [80, 95], resetEnabled: true, mutedProviders: [],
            armed: s2.armed)
        #expect(s3.notifications.first?.event == .threshold(80))
    }

    @Test func disabledThresholdNeverFires() {
        let runtimes: [ProviderID: ProviderRuntime] = [.claude: connected([window(used: 99)])]
        // Only 80 active → a 99% window fires 80, never 95.
        let s = NotificationService.plan(
            now: now, runtimes: runtimes, thresholds: [80], resetEnabled: true, mutedProviders: [],
            armed: [:])
        #expect(s.notifications.map(\.event) == [.threshold(80)])
    }

    // MARK: Reset — scheduled-ahead (primary path)

    @Test func futureResetSchedulesNotification() {
        let resetsAt = base.addingTimeInterval(5 * 3600)  // 5h in the future
        let runtimes: [ProviderID: ProviderRuntime] = [
            .claude: connected([window(used: 50, resetsAt: resetsAt)])
        ]
        let s = NotificationService.plan(
            now: base, runtimes: runtimes, thresholds: [80, 95], resetEnabled: true,
            mutedProviders: [], armed: [:])

        // A pending alert is scheduled at the known instant; nothing fires immediately.
        #expect(s.scheduledResets.count == 1)
        #expect(s.scheduledResets.first?.fireDate == resetsAt)
        #expect(s.scheduledResets.first?.notification.identifier == "claude.w.reset")
        #expect(!s.notifications.contains { $0.event == .reset })
        #expect(s.armed["claude|w"]?.scheduledResetAt == resetsAt)
    }

    @Test func shiftedResetReschedules() {
        let firstReset = base.addingTimeInterval(5 * 3600)
        let s1 = NotificationService.plan(
            now: base, runtimes: [.claude: connected([window(used: 50, resetsAt: firstReset)])],
            thresholds: [], resetEnabled: true, mutedProviders: [], armed: [:])
        #expect(s1.scheduledResets.first?.fireDate == firstReset)

        // Anthropic shifts the reset later (still no usage drop → not a rollover);
        // the planner reschedules the pending alert to the new instant.
        let shifted = base.addingTimeInterval(6 * 3600)
        let s2 = NotificationService.plan(
            now: base.addingTimeInterval(60),
            runtimes: [
                .claude: connected([window(used: 51, resetsAt: shifted)])
            ], thresholds: [], resetEnabled: true, mutedProviders: [], armed: s1.armed)
        #expect(s2.scheduledResets.count == 1)
        #expect(s2.scheduledResets.first?.fireDate == shifted)
    }

    @Test func noResetsAtSchedulesNothing() {
        let runtimes: [ProviderID: ProviderRuntime] = [.claude: connected([window(used: 50)])]
        let s = NotificationService.plan(
            now: now, runtimes: runtimes, thresholds: [], resetEnabled: true, mutedProviders: [],
            armed: [:])
        #expect(s.scheduledResets.isEmpty)
        #expect(s.cancelledIdentifiers.isEmpty)
    }

    // MARK: Reset — backstop (early rollover) vs on-time (left to schedule)

    @Test func onTimeResetIsLeftToScheduleNoImmediate() {
        // Reset boundary at base+5h; the detecting poll runs at base+6h (boundary
        // already passed → the scheduled alert has fired). No immediate backstop.
        let oldReset = base.addingTimeInterval(5 * 3600)
        let nextReset = base.addingTimeInterval(10 * 3600)

        let before: [ProviderID: ProviderRuntime] = [
            .claude: connected([window(used: 90, resetsAt: oldReset)])
        ]
        let s1 = NotificationService.plan(
            now: base.addingTimeInterval(4 * 3600), runtimes: before, thresholds: [80, 95],
            resetEnabled: true, mutedProviders: [], armed: [:])

        let after: [ProviderID: ProviderRuntime] = [
            .claude: connected([window(used: 4, resetsAt: nextReset)])
        ]
        let s2 = NotificationService.plan(
            now: base.addingTimeInterval(6 * 3600), runtimes: after, thresholds: [80, 95],
            resetEnabled: true, mutedProviders: [], armed: s1.armed)

        // On-time rollover → no immediate post (scheduled handled it); the ladder
        // re-arms and the next boundary is rescheduled.
        #expect(!s2.notifications.contains { $0.event == .reset })
        #expect(s2.armed["claude|w"]?.notifiedLevel == 0)
        #expect(s2.scheduledResets.contains { $0.fireDate == nextReset })
    }

    @Test func earlyResetFiresImmediateBackstopAndReschedules() {
        // Reset boundary announced at base+5h, but the provider rolls over early:
        // the detecting poll runs at base+2h, while oldReset is STILL in the future,
        // so the scheduled alert has not fired → an immediate backstop must post.
        let oldReset = base.addingTimeInterval(5 * 3600)
        let nextReset = base.addingTimeInterval(10 * 3600)

        let before: [ProviderID: ProviderRuntime] = [
            .claude: connected([window(used: 90, resetsAt: oldReset)])
        ]
        let s1 = NotificationService.plan(
            now: base.addingTimeInterval(1 * 3600), runtimes: before, thresholds: [80, 95],
            resetEnabled: true, mutedProviders: [], armed: [:])

        let after: [ProviderID: ProviderRuntime] = [
            .claude: connected([window(used: 4, resetsAt: nextReset)])
        ]
        let s2 = NotificationService.plan(
            now: base.addingTimeInterval(2 * 3600), runtimes: after, thresholds: [80, 95],
            resetEnabled: true, mutedProviders: [], armed: s1.armed)

        // Early rollover → immediate backstop (distinct identifier), ladder re-arms,
        // and the next boundary is (re)scheduled.
        #expect(s2.notifications.contains { $0.event == .reset })
        #expect(
            s2.notifications.contains {
                $0.event == .reset && $0.identifier == "claude.w.reset.late"
            })
        #expect(s2.armed["claude|w"]?.notifiedLevel == 0)
        #expect(s2.scheduledResets.contains { $0.fireDate == nextReset })
    }

    @Test func resetSuppressedWhenUsageStaysHigh() {
        let t1 = base.addingTimeInterval(5 * 3600)
        let t2 = t1.addingTimeInterval(5 * 3600)

        let before: [ProviderID: ProviderRuntime] = [
            .claude: connected([window(used: 90, resetsAt: t1)])
        ]
        let s1 = NotificationService.plan(
            now: base, runtimes: before, thresholds: [], resetEnabled: true, mutedProviders: [],
            armed: [:])

        // Reset instant moved forward but usage did not drop → not a real rollover,
        // so no backstop fires (the schedule simply tracks the new instant).
        let after: [ProviderID: ProviderRuntime] = [
            .claude: connected([window(used: 92, resetsAt: t2)])
        ]
        let s2 = NotificationService.plan(
            now: base.addingTimeInterval(60), runtimes: after, thresholds: [], resetEnabled: true,
            mutedProviders: [], armed: s1.armed)
        #expect(!s2.notifications.contains { $0.event == .reset })
    }

    @Test func resetToggleOffSuppressesBothScheduleAndBackstop() {
        let oldReset = base.addingTimeInterval(5 * 3600)
        let nextReset = base.addingTimeInterval(10 * 3600)

        // Even an early rollover produces nothing when reset alerts are off.
        let before: [ProviderID: ProviderRuntime] = [
            .claude: connected([window(used: 90, resetsAt: oldReset)])
        ]
        let s1 = NotificationService.plan(
            now: base.addingTimeInterval(1 * 3600), runtimes: before, thresholds: [],
            resetEnabled: false, mutedProviders: [], armed: [:])
        #expect(s1.scheduledResets.isEmpty)

        let after: [ProviderID: ProviderRuntime] = [
            .claude: connected([window(used: 4, resetsAt: nextReset)])
        ]
        let s2 = NotificationService.plan(
            now: base.addingTimeInterval(2 * 3600), runtimes: after, thresholds: [],
            resetEnabled: false, mutedProviders: [], armed: s1.armed)
        #expect(!s2.notifications.contains { $0.event == .reset })
        #expect(s2.scheduledResets.isEmpty)
    }

    @Test func mutingAfterSchedulingCancelsThePendingAlert() {
        let resetsAt = base.addingTimeInterval(5 * 3600)
        let s1 = NotificationService.plan(
            now: base, runtimes: [.claude: connected([window(used: 50, resetsAt: resetsAt)])],
            thresholds: [], resetEnabled: true, mutedProviders: [], armed: [:])
        #expect(s1.scheduledResets.count == 1)

        // The provider is muted on the next refresh → the pending scheduled alert is
        // cancelled (not left to fire).
        let s2 = NotificationService.plan(
            now: base.addingTimeInterval(60),
            runtimes: [.claude: connected([window(used: 51, resetsAt: resetsAt)])],
            thresholds: [], resetEnabled: true, mutedProviders: ["claude"], armed: s1.armed)
        #expect(s2.cancelledIdentifiers.contains("claude.w.reset"))
        #expect(s2.scheduledResets.isEmpty)
        #expect(s2.armed["claude|w"]?.scheduledResetAt == nil)
    }

    // MARK: Gating

    @Test func mutedProviderProducesNoNotificationsButStillTracks() {
        let runtimes: [ProviderID: ProviderRuntime] = [.claude: connected([window(used: 99)])]
        let s = NotificationService.plan(
            now: now, runtimes: runtimes, thresholds: [80, 95], resetEnabled: true,
            mutedProviders: ["claude"], armed: [:])
        #expect(s.notifications.isEmpty)
        // Armed state still advances so un-muting later does not replay old crossings.
        #expect(s.armed["claude|w"]?.notifiedLevel == 95)
    }

    @Test func disconnectedProviderIsSkipped() {
        let runtimes: [ProviderID: ProviderRuntime] = [
            .codex: ProviderRuntime(
                connection: .tokenExpired, windows: [], lastFetched: nil, errorMessage: nil,
                rawResponse: nil)
        ]
        let s = NotificationService.plan(
            now: now, runtimes: runtimes, thresholds: [80, 95], resetEnabled: true,
            mutedProviders: [], armed: [:])
        #expect(s.notifications.isEmpty)
    }

    @Test func belowAllThresholdsFiresNothing() {
        let runtimes: [ProviderID: ProviderRuntime] = [.codex: connected([window(used: 30)])]
        let s = NotificationService.plan(
            now: now, runtimes: runtimes, thresholds: [80, 95], resetEnabled: true,
            mutedProviders: [], armed: [:])
        #expect(s.notifications.isEmpty)
        #expect(s.armed["codex|w"]?.notifiedLevel == 0)
    }
}
