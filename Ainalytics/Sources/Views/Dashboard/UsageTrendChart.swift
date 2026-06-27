import Charts
import SwiftData
import SwiftUI

/// Daily peak-usage bars per provider, from accumulated `UsageSnapshot` history.
/// Each bar is one day's **peak utilization** — the highest percent-used window
/// seen that day — so a tall bar means a heavy day that pushed close to the cap.
///
/// A peak-per-day is a single clean number: it is reset-agnostic and never mixes
/// windows. The earlier remaining-% line silently switched which window it tracked
/// (the binding constraint moved between Session/Weekly), producing unreadable
/// jumps and a stray spike; the daily-peak bars remove that ambiguity.
///
/// On a fresh install there is little history, so an empty state shows until
/// snapshots accumulate.
struct UsageTrendChart: View {
    @Query private var snapshots: [UsageSnapshot]

    init() {
        // Two weeks keeps the grouped bars readable while the keep-all retention
        // policy (ARCHITECTURE §11) is still deferred.
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .distantPast
        _snapshots = Query(
            filter: #Predicate<UsageSnapshot> { $0.capturedAt >= cutoff },
            sort: \UsageSnapshot.capturedAt)
    }

    var body: some View {
        if bars.isEmpty {
            ContentUnavailableView {
                Label("Collecting data…", systemImage: "chart.bar.xaxis")
            } description: {
                Text("Daily usage will appear here as snapshots accumulate.")
            }
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Day", bar.day, unit: .day),
                y: .value("Peak usage", bar.peakUsed)
            )
            .foregroundStyle(by: .value("Provider", bar.providerName))
            .position(by: .value("Provider", bar.providerName))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale(
            domain: ProviderID.allCases.map(\.displayName),
            range: ProviderID.allCases.map { Theme.accent(for: $0) }
        )
        .chartYScale(domain: 0...100)
        .chartYAxisLabel("Peak usage")
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text(Double(percent) / 100, format: .percent.precision(.fractionLength(0)))
                    }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
    }

    /// One bar per provider per day: the day's peak utilization (max percent used
    /// across that provider's windows). A daily peak is reset-agnostic and never
    /// mixes windows, so there is no sawtooth and no silent window switching.
    private var bars: [DailyPeak] {
        var buckets: [ProviderID: [Date: Double]] = [:]
        let calendar = Calendar.current
        for snapshot in snapshots {
            guard let provider = ProviderID(rawValue: snapshot.providerID) else { continue }
            let percent = snapshot.limit > 0 ? min(100, snapshot.used / snapshot.limit * 100) : 0
            let day = calendar.startOfDay(for: snapshot.capturedAt)
            let current = buckets[provider, default: [:]][day] ?? 0
            buckets[provider, default: [:]][day] = max(current, percent)
        }
        return
            buckets
            .flatMap { provider, series in
                series.map { DailyPeak(provider: provider, day: $0.key, peakUsed: $0.value) }
            }
            .sorted { $0.day < $1.day }
    }
}

/// One charted bar: a provider's peak utilization on a single day.
private struct DailyPeak: Identifiable {
    let provider: ProviderID
    let day: Date
    let peakUsed: Double

    var id: String { "\(provider.rawValue)-\(day.timeIntervalSince1970)" }
    var providerName: String { provider.displayName }
}

#if DEBUG
    #Preview("Daily usage — seeded") {
        UsageTrendChart()
            .frame(width: 540, height: 260)
            .padding()
            .modelContainer(PreviewContainers.seeded)
    }

    #Preview("Daily usage — empty") {
        UsageTrendChart()
            .frame(width: 540, height: 260)
            .padding()
            .modelContainer(PreviewContainers.empty)
    }
#endif
