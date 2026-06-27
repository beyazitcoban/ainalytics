import Foundation
import Testing

@testable import Ainalytics

/// Tests for the Phase 12 widget data contract — `AppState.sharedSnapshot(pinned:)`
/// and the shared window-selection logic (`Provider.window(for:)`). `@MainActor`
/// because `AppState` is main-actor isolated.
@MainActor
struct SharedSnapshotTests {

    /// A fixed reset instant so `resetsAt` equality never drifts with the wall clock.
    private let reset = Date(timeIntervalSince1970: 1_700_000_000)

    private func window(_ percent: Double, kind: UsageWindowKind = .fiveHour, resetsAt: Date? = nil)
        -> UsageWindow
    {
        UsageWindow(
            id: "\(kind.rawValue)-\(percent)", kind: kind, title: nil, used: percent, limit: 100,
            resetsAt: resetsAt)
    }

    private func connected(_ windows: [UsageWindow]) -> ProviderRuntime {
        ProviderRuntime(
            connection: .connected, windows: windows, lastFetched: .now, errorMessage: nil,
            rawResponse: nil)
    }

    // MARK: - Snapshot membership

    @Test func includesConnectedProviderWithAllItsWindows() {
        let state = AppState.preview([
            .claude: connected([
                window(3, kind: .fiveHour, resetsAt: reset),
                window(69, kind: .weekly),
            ])
        ])
        let claude = state.sharedSnapshot(pinned: nil).providers.first { $0.providerID == "claude" }
        #expect(claude?.windows.count == 2)
        #expect(claude?.displayName == ProviderID.claude.displayName)
        // Carries each window's primitives through unchanged.
        let session = claude?.windows.first { $0.kind == "fiveHour" }
        #expect(session?.percentUsed == 3)
        #expect(session?.resetsAt == reset)
    }

    @Test func excludesDisconnectedProviders() {
        let state = AppState.preview([
            .claude: connected([window(50)]),
            .codex: ProviderRuntime(
                connection: .notInstalled, windows: [], lastFetched: nil, errorMessage: nil,
                rawResponse: nil),
        ])
        #expect(state.sharedSnapshot(pinned: nil).providers.map(\.providerID) == ["claude"])
    }

    @Test func excludesConnectedProviderWithNoWindow() {
        let state = AppState.preview([.claude: connected([])])
        #expect(state.sharedSnapshot(pinned: nil).providers.isEmpty)
    }

    @Test func providersFollowCanonicalOrder() {
        // Output order is `ProviderID.allCases`, independent of the dictionary order.
        let state = AppState.preview([
            .claude: connected([window(40)]),
            .codex: connected([window(50)]),
        ])
        #expect(
            state.sharedSnapshot(pinned: nil).providers.map(\.providerID)
                == ["claude", "codex"])
    }

    @Test func carriesPinnedProviderID() {
        let state = AppState.preview([.claude: connected([window(40)])])
        #expect(state.sharedSnapshot(pinned: .codex).pinnedProviderID == "codex")
        #expect(state.sharedSnapshot(pinned: nil).pinnedProviderID == nil)
    }

    // MARK: - Window selection (the configurable-widget logic)

    private func provider(_ windows: [(Double, UsageWindowKind)]) -> SharedUsageSnapshot.Provider {
        let state = AppState.preview([.claude: connected(windows.map { window($0.0, kind: $0.1) })])
        return state.sharedSnapshot(pinned: nil).providers.first { $0.providerID == "claude" }!
    }

    @Test func sessionMetricPicksFiveHourWindow() {
        let p = provider([(3, .fiveHour), (69, .weekly)])
        #expect(p.window(for: .session)?.kind == "fiveHour")
        #expect(p.window(for: .session)?.percentUsed == 3)
    }

    @Test func sessionMetricFallsBackToBindingWhenNoFiveHour() {
        // Codex-shape: only a Monthly window → Session falls back to the binding window.
        let p = provider([(9, .monthly)])
        #expect(p.window(for: .session)?.kind == "monthly")
    }

    @Test func autoMetricPicksBindingConstraint() {
        let p = provider([(10, .fiveHour), (80, .weekly), (5, .monthly)])
        #expect(p.window(for: .auto)?.percentUsed == 80)
        #expect(p.window(for: .auto)?.kind == "weekly")
    }

    @Test func weeklyAndMonthlyMetricsPickTheirKinds() {
        let p = provider([(3, .fiveHour), (69, .weekly), (40, .monthly)])
        #expect(p.window(for: .weekly)?.kind == "weekly")
        #expect(p.window(for: .monthly)?.kind == "monthly")
    }
}
