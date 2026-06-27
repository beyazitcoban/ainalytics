import SwiftUI

/// GitHub-style activity heatmap: 53 weeks × 7 weekdays, each day coloured by the
/// `Theme.heatmapRamp` according to that day's activity. The metric switches
/// between total tokens and message count (both come from the same scan, so the
/// toggle is instant). Fed by the real per-day log history (Phase 5) — replacing
/// Phase 4's snapshot-only trend as the historical surface.
struct ActivityHeatmap: View {
    let days: [DayActivity]
    @State private var metric: HeatmapMetric = .tokens

    private let calendar = Calendar.current
    private let weeks = LocalLogScanner.windowDays / 7
    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    monthLabels
                    grid
                }
            }
            .defaultScrollAnchor(.trailing)
            legend
        }
    }

    private var header: some View {
        HStack {
            Picker("Activity metric", selection: $metric) {
                Text("Tokens").tag(HeatmapMetric.tokens)
                Text("Messages").tag(HeatmapMetric.messages)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
    }

    private var grid: some View {
        HStack(spacing: gap) {
            ForEach(columns) { column in
                VStack(spacing: gap) {
                    ForEach(column.cells) { dayCell in
                        cellView(dayCell)
                    }
                }
            }
        }
    }

    private func cellView(_ dayCell: DayCell) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(dayCell.isFuture ? Color.clear : Theme.heatmapRamp[dayCell.level])
            .frame(width: cell, height: cell)
            .help(dayCell.tooltip)
            .accessibilityHidden(dayCell.isFuture)
    }

    private var monthLabels: some View {
        // A month label sits above the first column whose month differs from the
        // previous column's — the familiar GitHub month strip.
        HStack(spacing: gap) {
            ForEach(columns) { column in
                Text(column.monthLabel ?? "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    // Size to the label's natural width on one line first (no wrap),
                    // then reserve a single cell, left-aligned — the text overflows
                    // to the right over the following empty label slots (the GitHub
                    // month-strip idiom). Constraining to `cell` width first wrapped
                    // the 3-letter month abbreviations vertically.
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: cell, alignment: .leading)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Spacer()
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<Theme.heatmapRamp.count, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.heatmapRamp[level])
                    .frame(width: cell, height: cell)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Grid model

    private struct DayCell: Identifiable {
        let id = UUID()
        let level: Int
        let isFuture: Bool
        let tooltip: String
    }

    private struct Column: Identifiable {
        let id = UUID()
        let monthLabel: String?
        let cells: [DayCell]
    }

    /// Build the week-columns grid once per render, deriving the quantization
    /// thresholds from the visible non-zero days so colour scales to the data.
    private var columns: [Column] {
        let today = calendar.startOfDay(for: .now)
        let weekStartOfToday = startOfWeek(for: today)
        guard
            let gridStart = calendar.date(
                byAdding: .day, value: -(weeks - 1) * 7, to: weekStartOfToday)
        else { return [] }

        let valuesByDay = Dictionary(
            uniqueKeysWithValues: days.map { (calendar.startOfDay(for: $0.day), $0.value(for: metric)) }
        )
        let thresholds = quartileThresholds(of: valuesByDay.values.filter { $0 > 0 })

        var result: [Column] = []
        var previousMonth: Int?
        let unit = metric == .tokens ? String(localized: "tokens") : String(localized: "messages")

        for week in 0..<weeks {
            guard let weekStart = calendar.date(byAdding: .day, value: week * 7, to: gridStart)
            else { continue }
            var cells: [DayCell] = []
            for weekday in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: weekday, to: weekStart) else {
                    continue
                }
                let value = valuesByDay[date] ?? 0
                let isFuture = date > today
                let tooltip =
                    isFuture
                    ? ""
                    : "\(date.formatted(date: .abbreviated, time: .omitted)): \(value.formatted(.number.notation(.compactName))) \(unit)"
                cells.append(
                    DayCell(
                        level: level(of: value, thresholds: thresholds),
                        isFuture: isFuture, tooltip: tooltip))
            }
            let month = calendar.component(.month, from: weekStart)
            let label = month != previousMonth ? monthName(month) : nil
            previousMonth = month
            result.append(Column(monthLabel: label, cells: cells))
        }
        return result
    }

    private func startOfWeek(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    private func monthName(_ month: Int) -> String {
        let symbols = calendar.shortMonthSymbols
        return (1...12).contains(month) ? symbols[month - 1] : ""
    }

    /// 0 → empty; 1…4 → quartile buckets of the visible non-zero days.
    private func level(of value: Int, thresholds: [Int]) -> Int {
        guard value > 0, thresholds.count == 3 else { return 0 }
        if value <= thresholds[0] { return 1 }
        if value <= thresholds[1] { return 2 }
        if value <= thresholds[2] { return 3 }
        return 4
    }

    private func quartileThresholds(of values: some Collection<Int>) -> [Int] {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return [] }
        func percentile(_ p: Double) -> Int {
            let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))
            return sorted[index]
        }
        return [percentile(0.25), percentile(0.5), percentile(0.75)]
    }
}

#if DEBUG
    #Preview("Heatmap — seeded") {
        ActivityHeatmap(days: PreviewData.sampleScanResult.days)
            .padding()
            .frame(width: 820, height: 200)
    }
#endif
