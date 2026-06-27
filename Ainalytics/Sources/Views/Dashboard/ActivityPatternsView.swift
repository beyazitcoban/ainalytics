import Charts
import SwiftUI

/// "Activity patterns" — *when* you work, from the local CLI logs (Phase 10). A
/// daily-activity streak badge plus an hour-of-day bar chart (peak hours), both
/// derived from the same scan via `InsightsEngine`. The chart shares the heatmap's
/// tokens/messages metric language and the app's per-provider accent colours; an
/// honest "not enough activity" state shows instead of an empty grid.
struct ActivityPatternsView: View {
    let insights: ActivityInsights
    @State private var metric: HeatmapMetric = .tokens

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header
                if insights.hasPeakData {
                    chart
                    if let peak = insights.peakHour(for: metric) {
                        Text("Most active around \(hourLabel(peak))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not enough activity yet to show patterns.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            streakBadge
            Spacer(minLength: Theme.Spacing.md)
            Picker("Activity metric", selection: $metric) {
                Text("Tokens").tag(HeatmapMetric.tokens)
                Text("Messages").tag(HeatmapMetric.messages)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var streakBadge: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(insights.streak.current > 0 ? Theme.warning : Color.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(insights.streak.current)-day streak")
                    .font(.headline)
                    .monospacedDigit()
                if insights.streak.longest > 0 {
                    Text("Longest: \(insights.streak.longest) days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(insights.peakHours) { hourActivity in
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    let value =
                        metric == .tokens
                        ? (hourActivity.tokensByProvider[provider] ?? 0)
                        : (hourActivity.messagesByProvider[provider] ?? 0)
                    if value > 0 {
                        BarMark(
                            x: .value("Hour", hourActivity.hour),
                            y: .value("Activity", value)
                        )
                        .foregroundStyle(by: .value("Provider", provider.displayName))
                    }
                }
            }
        }
        .chartForegroundStyleScale(
            domain: ProviderID.allCases.map(\.displayName),
            range: ProviderID.allCases.map { Theme.accent(for: $0) }
        )
        .chartXScale(domain: 0...23)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hour = value.as(Int.self) { Text(verbatim: hourLabel(hour)) }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 160)
    }

    /// A localized hour-of-day label (e.g. "14:00" or "2 PM" per the user's locale).
    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour)) ?? .now
        return date.formatted(.dateTime.hour())
    }
}

#if DEBUG
    #Preview("Activity patterns — seeded") {
        ActivityPatternsView(
            insights: InsightsEngine.insights(from: PreviewData.sampleScanResult)
        )
        .padding()
        .frame(width: 460)
    }
#endif
