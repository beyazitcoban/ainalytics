import Foundation
import Testing

@testable import Ainalytics

/// Tests for the Phase 17 window selectors on `ProviderRuntime` — the general vs
/// scoped split and the selectors that must ignore scoped windows so a hot model
/// limit never hijacks the headline, forecast, or renewal date.
struct ProviderRuntimeTests {

    private func window(
        id: String, kind: UsageWindowKind = .weekly, used: Double,
        scope: UsageWindowScope = .general, isActive: Bool = true, title: String? = nil,
        resetsAt: Date? = nil
    ) -> UsageWindow {
        UsageWindow(
            id: id, kind: kind, title: title, used: used, limit: 100, resetsAt: resetsAt,
            scope: scope, isActive: isActive)
    }

    /// Two general windows + a hot scoped model (Opus 90%) + a scoped surface.
    private var mixed: ProviderRuntime {
        ProviderRuntime(
            connection: .connected,
            windows: [
                window(id: "five_hour", kind: .fiveHour, used: 40),
                window(id: "seven_day", kind: .weekly, used: 30),
                window(id: "m_opus", used: 90, scope: .model("Opus"), title: "Opus"),
                window(id: "s_cowork", used: 60, scope: .surface("Cowork"), title: "Cowork"),
            ],
            lastFetched: nil, errorMessage: nil, rawResponse: nil)
    }

    @Test func generalWindowsExcludeScoped() {
        #expect(mixed.generalWindows.map(\.id) == ["five_hour", "seven_day"])
    }

    @Test func scopedWindowsAreOnlyModelAndSurface() {
        #expect(Set(mixed.scopedWindows.map(\.id)) == ["m_opus", "s_cowork"])
    }

    /// The headline is the highest-used GENERAL window — the 90% scoped Opus window is
    /// ignored, so the menu bar / widget never silently jump to a model window.
    @Test func primaryWindowIgnoresHotScopedModel() {
        #expect(mixed.primaryWindow?.id == "five_hour")
    }

    /// "Most active model" narrows to `.model` scope — the surface (Cowork) window is
    /// not a model, so the model-scoped Opus wins.
    @Test func mostActiveModelWindowNarrowsToModelScope() {
        #expect(mixed.mostActiveModelWindow?.id == "m_opus")
        #expect(mixed.mostActiveModelWindow?.title == "Opus")
    }

    /// The renewal-date proxy is the longest general cycle (weekly > five-hour); the
    /// scoped weekly windows are excluded from the choice.
    @Test func subscriptionWindowIsLongestGeneralCycle() {
        #expect(mixed.subscriptionWindow?.id == "seven_day")
    }

    /// A Codex-shape runtime (general only) has no scoped windows and its selectors
    /// behave exactly as before Phase 17.
    @Test func generalOnlyRuntimeHasNoScopedWindows() {
        let runtime = ProviderRuntime(
            connection: .connected,
            windows: [window(id: "monthly", kind: .monthly, used: 41)],
            lastFetched: nil, errorMessage: nil, rawResponse: nil)
        #expect(runtime.scopedWindows.isEmpty)
        #expect(runtime.generalWindows.count == 1)
        #expect(runtime.primaryWindow?.id == "monthly")
        #expect(runtime.mostActiveModelWindow == nil)
    }
}
