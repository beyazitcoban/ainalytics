import Testing

@testable import Ainalytics

/// Placeholder test — confirms the unit-test target builds and runs.
/// Real feature tests live in the dedicated `*Tests` files.
@MainActor
struct AinalyticsTests {
    @Test func appStateInitializes() {
        _ = AppState()
        #expect(true)
    }
}
