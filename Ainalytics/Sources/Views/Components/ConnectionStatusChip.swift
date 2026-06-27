import SwiftUI

/// A compact capsule badge for a degraded provider connection — icon + text + the
/// state's colour (never colour alone, code-principles §7). Shared by the menu-bar
/// row, the dashboard card, and the cost card so the degraded language is identical
/// everywhere. The connection's display strings/symbol/colour live on
/// `ProviderConnection` (see `ProvidersView`).
struct ConnectionStatusChip: View {
    let connection: ProviderConnection

    var body: some View {
        Label(connection.statusText, systemImage: connection.statusSymbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(connection.statusColor)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(connection.statusColor.opacity(0.14), in: Capsule())
    }
}
