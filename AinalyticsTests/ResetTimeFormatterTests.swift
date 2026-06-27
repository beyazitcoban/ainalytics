import Foundation
import Testing

@testable import Ainalytics

/// Unit tests for the pure absolute-time core of `ResetTimeFormatter`.
///
/// The relative branch is a self-updating SwiftUI `Text` (not a plain string), so
/// the testable logic is `absoluteString(for:now:calendar:locale:)`: it must show
/// **time only** when the reset falls on the same calendar day as `now`, and a
/// **short weekday + time** otherwise. All inputs (`now` / `calendar` / `locale`)
/// are injected so the result is independent of the host machine's clock + region.
struct ResetTimeFormatterTests {

    // MARK: Fixtures — a fixed calendar/locale so assertions are deterministic.

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }

    private let locale = Locale(identifier: "en_US")

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// The abbreviated weekday for `date` under the same fixed calendar/locale/tz,
    /// so the contains-assertions don't depend on the host region.
    private func weekdayToken(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// The time-only string under the same fixed calendar/locale/tz.
    private func timeToken(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    // MARK: Same-day → time only

    @Test func sameDayShowsTimeOnlyNoWeekday() {
        let now = date(2026, 6, 27, 9, 0)
        let reset = date(2026, 6, 27, 14, 30)
        let s = ResetTimeFormatter.absoluteString(
            for: reset, now: now, calendar: calendar, locale: locale)

        #expect(s == timeToken(reset))
        #expect(!s.contains(weekdayToken(reset)))
    }

    // MARK: Different day → weekday + time

    @Test func differentDayShowsWeekdayAndTime() {
        let now = date(2026, 6, 27, 9, 0)
        let reset = date(2026, 6, 30, 14, 30)  // 3 days later
        let s = ResetTimeFormatter.absoluteString(
            for: reset, now: now, calendar: calendar, locale: locale)

        #expect(s.contains(weekdayToken(reset)))
        #expect(s.contains(timeToken(reset)))
    }

    /// One hour later but across midnight counts as a different day (weekday shows),
    /// even though a relative duration would read "1 hr".
    @Test func acrossMidnightIsDifferentDay() {
        let now = date(2026, 6, 27, 23, 30)
        let reset = date(2026, 6, 28, 0, 30)
        let s = ResetTimeFormatter.absoluteString(
            for: reset, now: now, calendar: calendar, locale: locale)

        #expect(s.contains(weekdayToken(reset)))
    }

    /// Different hour, same calendar day → still time only (the same-day branch is
    /// keyed on the calendar day, not on a 24-hour delta).
    @Test func sameDayDifferentHourStaysTimeOnly() {
        let now = date(2026, 6, 27, 0, 5)
        let reset = date(2026, 6, 27, 23, 55)
        let s = ResetTimeFormatter.absoluteString(
            for: reset, now: now, calendar: calendar, locale: locale)

        #expect(s == timeToken(reset))
        #expect(!s.contains(weekdayToken(reset)))
    }
}
