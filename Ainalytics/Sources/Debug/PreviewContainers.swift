#if DEBUG
    import Foundation
    import SwiftData

    /// In-memory SwiftData containers for SwiftUI Previews. Independent of the real
    /// store so Previews never touch persisted data.
    enum PreviewContainers {
        static let empty: ModelContainer = {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(
                for: UsageSnapshot.self, ProviderState.self,
                configurations: config
            )
        }()

        /// A week of rising snapshots for Claude + Codex so the trend chart renders
        /// in Previews. In-memory only. `@MainActor` because seeding touches the
        /// container's main-actor-isolated `mainContext`.
        @MainActor static let seeded: ModelContainer = {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try! ModelContainer(
                for: UsageSnapshot.self, ProviderState.self, configurations: config)
            let context = container.mainContext
            let now = Date.now
            for daysBack in stride(from: 7, through: 0, by: -1) {
                let captured = now.addingTimeInterval(Double(-daysBack) * 86_400)
                let progress = Double(7 - daysBack)
                context.insert(
                    UsageSnapshot(
                        providerID: ProviderID.claude.rawValue, capturedAt: captured,
                        windowTypeRaw: UsageWindowKind.weekly.rawValue,
                        used: 30 + progress * 8, limit: 100, resetsAt: nil))
                context.insert(
                    UsageSnapshot(
                        providerID: ProviderID.codex.rawValue, capturedAt: captured,
                        windowTypeRaw: UsageWindowKind.monthly.rawValue,
                        used: 20 + progress * 5, limit: 100, resetsAt: nil))
            }
            try? context.save()
            return container
        }()

        /// A rising current-cycle series (no reset drop) so the burn-rate forecast
        /// projects a run-out: Claude's weekly window climbs fast toward its reset
        /// (a warning), Codex's monthly window climbs slowly (on track). In-memory only.
        @MainActor static let burnRate: ModelContainer = {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try! ModelContainer(
                for: UsageSnapshot.self, ProviderState.self, configurations: config)
            let context = container.mainContext
            let now = Date.now
            let claudeReset = now.addingTimeInterval(36 * 3_600)
            let codexReset = now.addingTimeInterval(18 * 86_400)
            for step in 0...5 {
                let captured = now.addingTimeInterval(Double(step - 5) * 12 * 3_600)
                context.insert(
                    UsageSnapshot(
                        providerID: ProviderID.claude.rawValue, capturedAt: captured,
                        windowTypeRaw: UsageWindowKind.weekly.rawValue,
                        used: 50 + Double(step) * 8.5, limit: 100, resetsAt: claudeReset))
                context.insert(
                    UsageSnapshot(
                        providerID: ProviderID.codex.rawValue, capturedAt: captured,
                        windowTypeRaw: UsageWindowKind.monthly.rawValue,
                        used: 22 + Double(step) * 1.6, limit: 100, resetsAt: codexReset))
            }
            try? context.save()
            return container
        }()
    }

    /// Sample provider runtimes for dashboard / card Previews — connected (Claude
    /// with model windows) and single-window (Codex monthly).
    enum PreviewData {
        static var mixedRuntimes: [ProviderID: ProviderRuntime] {
            [
                .claude: ProviderRuntime(
                    connection: .connected,
                    windows: [
                        UsageWindow(
                            id: "five_hour", kind: .fiveHour, title: nil, used: 64, limit: 100,
                            resetsAt: .now.addingTimeInterval(9_000)),
                        UsageWindow(
                            id: "seven_day", kind: .weekly, title: nil, used: 71, limit: 100,
                            resetsAt: .now.addingTimeInterval(420_000)),
                        // Scoped (Phase 17): model/surface weekly limits — an active
                        // model, an active surface, and an inactive model.
                        UsageWindow(
                            id: "seven_day_model_Opus", kind: .weekly, title: "Opus", used: 88,
                            limit: 100, resetsAt: .now.addingTimeInterval(420_000),
                            scope: .model("Opus"), isActive: true),
                        UsageWindow(
                            id: "seven_day_surface_Cowork", kind: .weekly, title: "Cowork",
                            used: 34, limit: 100, resetsAt: .now.addingTimeInterval(420_000),
                            scope: .surface("Cowork"), isActive: true),
                        UsageWindow(
                            id: "seven_day_model_Fable", kind: .weekly, title: "Fable", used: 12,
                            limit: 100, resetsAt: .now.addingTimeInterval(420_000),
                            scope: .model("Fable"), isActive: false),
                    ],
                    lastFetched: .now, errorMessage: nil, rawResponse: nil),
                .codex: ProviderRuntime(
                    connection: .connected,
                    windows: [
                        UsageWindow(
                            id: "monthly", kind: .monthly, title: nil, used: 41, limit: 100,
                            resetsAt: .now.addingTimeInterval(1_900_000))
                    ],
                    lastFetched: .now, errorMessage: nil, rawResponse: nil),
            ]
        }

        /// A few weeks of synthetic per-day activity (Claude + Codex) plus two
        /// model totals and an hour-of-day curve, for the heatmap / patterns /
        /// dashboard / cost Previews.
        static var sampleScanResult: LogScanResult {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            var days: [DayActivity] = []
            for back in stride(from: 45, through: 0, by: -1) {
                guard let day = calendar.date(byAdding: .day, value: -back, to: today) else {
                    continue
                }
                let weekday = calendar.component(.weekday, from: day)
                let base = (weekday == 1 || weekday == 7) ? 0 : (45 - back)
                guard base > 0 else { continue }
                days.append(
                    DayActivity(
                        day: day,
                        tokensByProvider: [
                            .claude: base * 12_000 + (back % 5) * 3_000, .codex: base * 4_000,
                        ],
                        messagesByProvider: [.claude: base * 3, .codex: base]))
            }
            return LogScanResult(
                days: days, models: sampleModels, hours: sampleHours)
        }

        /// A plausible work-day curve — quiet overnight, ramping from ~9h, peaking
        /// mid-afternoon — so the peak-hours chart renders in Previews.
        static var sampleHours: [HourActivity] {
            let shape: [Int: Double] = [
                8: 0.3, 9: 0.6, 10: 0.85, 11: 0.95, 12: 0.7, 13: 0.8, 14: 1.0, 15: 0.95,
                16: 0.8, 17: 0.6, 18: 0.4, 21: 0.35, 22: 0.5, 23: 0.3,
            ]
            return shape.map { hour, weight in
                HourActivity(
                    hour: hour,
                    tokensByProvider: [
                        .claude: Int(weight * 220_000), .codex: Int(weight * 70_000),
                    ],
                    messagesByProvider: [.claude: Int(weight * 40), .codex: Int(weight * 14)])
            }
            .sorted { $0.hour < $1.hour }
        }

        static var sampleModels: [ModelUsage] {
            [
                ModelUsage(
                    provider: .claude, model: "claude-opus-4-8", inputTokens: 1_200_000,
                    outputTokens: 240_000, cacheReadTokens: 8_400_000, cacheWriteTokens: 1_900_000),
                ModelUsage(
                    provider: .codex, model: "gpt-5.5", inputTokens: 480_000, outputTokens: 90_000,
                    cacheReadTokens: 1_200_000, cacheWriteTokens: 0),
            ]
        }

        static var sampleCosts: [ProviderCost] {
            [
                ProviderCost(
                    provider: .claude,
                    models: [ModelCost(usage: sampleModels[0], usd: 31.42)]),
                ProviderCost(
                    provider: .codex,
                    models: [ModelCost(usage: sampleModels[1], usd: 5.13)]),
            ]
        }

        /// Preferences with subscription prices set, so the ROI preview renders a
        /// value ratio instead of the "set your price" prompt.
        @MainActor static var previewPreferencesWithPrices: AppPreferences {
            let preferences = AppPreferences()
            preferences.providerMonthlyPriceUSD = [
                ProviderID.claude.rawValue: 100, ProviderID.codex.rawValue: 20,
            ]
            return preferences
        }
    }
#endif
