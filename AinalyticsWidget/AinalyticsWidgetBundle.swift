import SwiftUI
import WidgetKit

/// The widget extension's entry point. A bundle so more widgets can be added later
/// without another target. macOS surfaces these in Notification Center / on the desktop.
@main
struct AinalyticsWidgetBundle: WidgetBundle {
    var body: some Widget {
        AinalyticsWidget()
    }
}
