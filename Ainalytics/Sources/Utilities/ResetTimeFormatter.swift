import SwiftUI

/// Where a reset/renewal time is shown, and with which verb — selects which
/// localized key the shared `ResetTimeFormatter` uses.
enum ResetPhrasing {
    /// "Resets in/at %@" — a limit window rolling over (the menu-bar `ProviderRow`).
    case reset
    /// "Renews in/at %@" — a subscription window renewing (the dashboard footer).
    case renew
    /// No verb — just the value, kept compact (the dashboard gauge cell).
    case bare
}

/// Renders a window's `resetsAt` as either a relative, self-updating duration
/// ("4 sa. sonra sıfırlanır") or an absolute time ("14:30'da sıfırlanır"), per
/// `AppPreferences.resetDisplayStyle`. Shared by all three reset/renewal sites
/// (the menu-bar `ProviderRow`, the dashboard `ProviderUsageCard` gauge + footer)
/// so the choice applies everywhere from one place.
enum ResetTimeFormatter {

    /// The `Text` to show for `date`, honoring the display style + phrasing.
    /// - Relative: the date interpolates with `.relative` style so SwiftUI keeps
    ///   the countdown live; the per-language key reorders the sentence.
    /// - Absolute: a locale-aware static time string (same-day → time only,
    ///   otherwise short weekday + time) wrapped in the matching "at" key.
    static func text(
        for date: Date,
        style: ResetDisplayStyle,
        phrasing: ResetPhrasing
    ) -> Text {
        switch style {
        case .relativeDuration:
            switch phrasing {
            case .reset: return Text("Resets in \(date, style: .relative)")
            case .renew: return Text("Renews in \(date, style: .relative)")
            case .bare: return Text(date, style: .relative)
            }
        case .absoluteTime:
            let value = absoluteString(for: date)
            switch phrasing {
            case .reset: return Text("Resets at \(value)")
            case .renew: return Text("Renews at \(value)")
            case .bare: return Text(verbatim: value)
            }
        }
    }

    /// The absolute time string: just the time when `date` falls on the same day
    /// as `now`, otherwise a short weekday prefix + time. Locale-aware via
    /// `.dateTime`. Pure (injectable `now` / `calendar` / `locale`) so it is
    /// unit-testable independent of the host machine's clock and region.
    static func absoluteString(
        for date: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let sameDay = calendar.isDate(date, inSameDayAs: now)
        var style: Date.FormatStyle =
            sameDay
            ? .dateTime.hour().minute()
            : .dateTime.weekday(.abbreviated).hour().minute()
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
