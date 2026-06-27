import Foundation
import Testing

@testable import Ainalytics

/// Pure-function tests for the Phase 10 `InsightsEngine`. Deterministic — a fixed
/// UTC calendar and a fixed "now" — so streak boundaries never drift with the test
/// machine's timezone or the wall clock (Rule #4).
struct InsightsEngineTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// A fixed instant standing in for "today".
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// A day `offset` days from `now` (negative = past) with `messages` activity.
    private func day(_ offset: Int, messages: Int = 5) -> DayActivity {
        let base = calendar.startOfDay(for: now)
        let date = calendar.date(byAdding: .day, value: offset, to: base)!
        return DayActivity(
            day: date,
            tokensByProvider: [.claude: messages * 1_000],
            messagesByProvider: [.claude: messages])
    }

    // MARK: - Streak

    @Test func emptyHistoryHasNoStreak() {
        #expect(InsightsEngine.streak(days: [], calendar: calendar, now: now) == .zero)
    }

    @Test func consecutiveDaysEndingTodayCounts() {
        let streak = InsightsEngine.streak(
            days: [day(0), day(-1), day(-2)], calendar: calendar, now: now)
        #expect(streak.current == 3)
        #expect(streak.longest == 3)
    }

    @Test func gapBreaksCurrentButLongestSurvives() {
        // Today alone, then a separate 3-day run two days back (a one-day gap).
        let streak = InsightsEngine.streak(
            days: [day(0), day(-2), day(-3), day(-4)], calendar: calendar, now: now)
        #expect(streak.current == 1)
        #expect(streak.longest == 3)
    }

    @Test func streakEndingYesterdayStillCounts() {
        // Today is idle but not yet over — a run ending yesterday is still "current".
        let streak = InsightsEngine.streak(
            days: [day(-1), day(-2)], calendar: calendar, now: now)
        #expect(streak.current == 2)
        #expect(streak.longest == 2)
    }

    @Test func onlyOldActivityHasNoCurrentStreak() {
        let streak = InsightsEngine.streak(
            days: [day(-3), day(-4)], calendar: calendar, now: now)
        #expect(streak.current == 0)
        #expect(streak.longest == 2)
    }

    @Test func zeroMessageDaysAreNotActive() {
        // Today logged nothing (0 messages) → inactive; the streak ends yesterday.
        let streak = InsightsEngine.streak(
            days: [day(0, messages: 0), day(-1)], calendar: calendar, now: now)
        #expect(streak.current == 1)
        #expect(streak.longest == 1)
    }

    // MARK: - Consumption

    @Test func cacheHitRatioIsCachedOverTotalInput() {
        let models = [
            ModelUsage(
                provider: .claude, model: "claude-opus-4-8", inputTokens: 100, outputTokens: 50,
                cacheReadTokens: 300, cacheWriteTokens: 0)
        ]
        let insight = InsightsEngine.consumption(models: models).first
        // 300 cached of (100 + 300) input = 0.75.
        #expect(insight?.cacheHitRatio == 0.75)
        #expect(insight?.inputTokens == 100)
        #expect(insight?.outputTokens == 50)
    }

    @Test func noInputYieldsNilCacheRatio() {
        let models = [
            ModelUsage(
                provider: .codex, model: "gpt-5.5", inputTokens: 0, outputTokens: 40,
                cacheReadTokens: 0, cacheWriteTokens: 0)
        ]
        #expect(InsightsEngine.consumption(models: models).first?.cacheHitRatio == nil)
    }

    @Test func modelMixFoldsTailIntoOtherAndSharesSumToOne() {
        // Six models, default top-4 → 4 named + one "Other".
        let models = (1...6).map { index in
            ModelUsage(
                provider: .claude, model: "model-\(index)",
                inputTokens: index * 100, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0)
        }
        let mix = InsightsEngine.consumption(models: models).first!.modelMix
        #expect(mix.count == 5)
        #expect(mix.last?.isOther == true)
        let total = mix.reduce(0.0) { $0 + $1.share }
        #expect(abs(total - 1.0) < 0.0001)
        // The mix is ordered by tokens descending (model-6 is the largest).
        #expect(mix.first?.model == "model-6")
    }

    @Test func providersAreReturnedInCanonicalOrder() {
        let models = [
            ModelUsage(
                provider: .codex, model: "gpt-5.5", inputTokens: 10, outputTokens: 10,
                cacheReadTokens: 0, cacheWriteTokens: 0),
            ModelUsage(
                provider: .claude, model: "claude-opus-4-8", inputTokens: 10, outputTokens: 10,
                cacheReadTokens: 0, cacheWriteTokens: 0),
        ]
        let order = InsightsEngine.consumption(models: models).map(\.provider)
        #expect(order == [.claude, .codex])
    }

    // MARK: - Peak hours + integration

    @Test func peakHourPicksTheBusiestHour() {
        let hours = [
            HourActivity(hour: 9, tokensByProvider: [.claude: 100], messagesByProvider: [.claude: 2]),
            HourActivity(hour: 14, tokensByProvider: [.claude: 500], messagesByProvider: [.claude: 9]),
            HourActivity(hour: 22, tokensByProvider: [.claude: 300], messagesByProvider: [.claude: 5]),
        ]
        let insights = InsightsEngine.insights(
            from: LogScanResult(days: [], models: [], hours: hours),
            calendar: calendar, now: now)
        #expect(insights.peakHour(for: .tokens) == 14)
        #expect(insights.hasPeakData)
    }

    @Test func emptyResultHasNoPeakData() {
        let insights = InsightsEngine.insights(from: .empty, calendar: calendar, now: now)
        #expect(insights.peakHour(for: .tokens) == nil)
        #expect(!insights.hasPeakData)
        #expect(insights.streak == .zero)
    }
}
