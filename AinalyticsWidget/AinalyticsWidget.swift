import SwiftUI
import WidgetKit

/// The Ainalytics usage widget. An `AppIntentConfiguration` so a right-click →
/// "Edit Widget" lets the user pick the provider and the usage window (the snapshot
/// the main app writes carries every window). The small family headlines one
/// provider's chosen window; the medium family shows all providers (Automatic) or
/// one provider's windows (a specific provider).
struct AinalyticsWidget: Widget {
    let kind = "AinalyticsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind, intent: AinalyticsWidgetConfiguration.self,
            provider: AinalyticsWidgetProvider()
        ) { entry in
            AinalyticsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Ainalytics")
        .description(Text("See your AI usage at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
