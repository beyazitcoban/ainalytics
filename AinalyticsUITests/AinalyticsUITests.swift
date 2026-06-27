import XCTest

/// Placeholder UI test — confirms the UI-test target builds.
/// Real flow tests arrive later.
final class AinalyticsUITests: XCTestCase {
    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
    }
}
