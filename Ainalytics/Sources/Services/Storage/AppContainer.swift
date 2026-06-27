import Foundation
import SwiftData

/// The app's SwiftData container.
///
/// App Sandbox is OFF (kurgulama Phase F.1b), so the store lives at
/// `~/Library/Application Support/Ainalytics/default.store` (ARCHITECTURE §4a.ii).
enum AppContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(
                for: UsageSnapshot.self, ProviderState.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false)
            )
        } catch {
            fatalError("ModelContainer failed: \(error)")
        }
    }()
}
