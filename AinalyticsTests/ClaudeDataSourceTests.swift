import Foundation
import Testing

@testable import Ainalytics

/// Tests for the Phase 17 Claude usage parse — the `limits` array (general +
/// model/surface-scoped, with `is_active`) as the primary path, and the legacy
/// top-level keys as the graceful fallback. Exercises `ClaudeDataSource.parseWindows`
/// directly against captured-shape JSON fixtures (no live endpoint).
struct ClaudeDataSourceTests {

    private func windows(_ json: String) -> [UsageWindow] {
        ClaudeDataSource.parseWindows(from: Data(json.utf8))
    }

    private func window(_ windows: [UsageWindow], id: String) -> UsageWindow? {
        windows.first { $0.id == id }
    }

    // MARK: - `limits` array (primary)

    /// The live shape: top-level Session/Weekly PLUS a `limits` array carrying the
    /// plan-wide windows again + a scoped model (inactive) + a scoped surface. When
    /// `limits` is present it is authoritative — the general windows come from it (so
    /// no duplication with the top-level keys).
    @Test func parsesLimitsArrayIntoGeneralAndScoped() {
        let json = """
            {
              "five_hour": { "utilization": 86, "resets_at": "2026-07-16T20:00:00Z" },
              "seven_day": { "utilization": 31, "resets_at": "2026-07-20T00:00:00Z" },
              "limits": [
                { "group": "session", "percent": 86, "resets_at": "2026-07-16T20:00:00Z", "is_active": true },
                { "group": "weekly", "percent": 31, "resets_at": "2026-07-20T00:00:00Z", "is_active": true },
                { "group": "weekly", "percent": 6, "resets_at": "2026-07-20T00:00:00Z", "is_active": false,
                  "scope": { "model": { "display_name": "Fable" } } },
                { "group": "weekly", "percent": 42, "resets_at": "2026-07-20T00:00:00Z", "is_active": true,
                  "scope": { "surface": "cowork" } }
              ]
            }
            """
        let result = windows(json)
        // Exactly the 4 `limits` elements (the top-level keys are not double-counted).
        #expect(result.count == 4)

        let general = result.filter(\.isGeneral)
        #expect(Set(general.map(\.id)) == ["five_hour", "seven_day"])
        #expect(window(result, id: "five_hour")?.kind == .fiveHour)
        #expect(window(result, id: "five_hour")?.used == 86)
        #expect(window(result, id: "seven_day")?.kind == .weekly)

        let fable = window(result, id: "seven_day_model_Fable")
        #expect(fable?.scope == .model("Fable"))
        #expect(fable?.title == "Fable")
        #expect(fable?.isActive == false)
        #expect(fable?.used == 6)

        let cowork = window(result, id: "seven_day_surface_Cowork")
        #expect(cowork?.scope == .surface("Cowork"))  // humanized from "cowork"
        #expect(cowork?.isActive == true)
    }

    /// A `limits` element with no percent (utilization/percent) is skipped, not fatal.
    @Test func skipsLimitsElementMissingPercent() {
        let json = """
            {
              "limits": [
                { "group": "session", "percent": 12, "is_active": true },
                { "group": "weekly", "is_active": true }
              ]
            }
            """
        let result = windows(json)
        #expect(result.count == 1)
        #expect(result.first?.kind == .fiveHour)
    }

    /// When `limits` carries only scoped windows, the first-class Session/Weekly are
    /// backfilled from the legacy top-level keys so the headline never vanishes.
    @Test func backfillsGeneralWhenLimitsAreScopedOnly() {
        let json = """
            {
              "five_hour": { "utilization": 55, "resets_at": "2026-07-16T20:00:00Z" },
              "seven_day": { "utilization": 22, "resets_at": "2026-07-20T00:00:00Z" },
              "limits": [
                { "group": "weekly", "percent": 8, "is_active": true,
                  "scope": { "model": { "display_name": "Sonnet" } } }
              ]
            }
            """
        let result = windows(json)
        #expect(Set(result.filter(\.isGeneral).map(\.id)) == ["five_hour", "seven_day"])
        #expect(result.filter { !$0.isGeneral }.map(\.id) == ["seven_day_model_Sonnet"])
    }

    // MARK: - Legacy top-level keys (fallback)

    /// No `limits` array → the old top-level parse. Session/Weekly are general; the
    /// old model keys map to `.model` scope so they still surface in the scoped section.
    @Test func fallsBackToLegacyKeysWhenNoLimitsArray() {
        let json = """
            {
              "five_hour": { "utilization": 50, "resets_at": "2026-07-16T20:00:00Z" },
              "seven_day": { "utilization": 20, "resets_at": "2026-07-20T00:00:00Z" },
              "seven_day_opus": { "utilization": 70, "resets_at": "2026-07-20T00:00:00Z" }
            }
            """
        let result = windows(json)
        #expect(result.count == 3)
        #expect(Set(result.filter(\.isGeneral).map(\.id)) == ["five_hour", "seven_day"])
        let opus = window(result, id: "seven_day_opus")
        #expect(opus?.scope == .model("Opus"))
        #expect(opus?.title == "Opus")
    }

    /// An empty `limits` array is treated as absent → legacy fallback.
    @Test func emptyLimitsArrayFallsBackToLegacy() {
        let json = """
            { "five_hour": { "utilization": 10 }, "limits": [] }
            """
        let result = windows(json)
        #expect(result.count == 1)
        #expect(result.first?.isGeneral == true)
    }

    /// Non-JSON / unparseable body yields an empty list (never a throw).
    @Test func garbageBodyYieldsEmpty() {
        #expect(windows("not json at all").isEmpty)
    }
}
