import Foundation
import Observation

/// Owns the dashboard's log-derived data: the activity heatmap result and the
/// API-equivalent costs. Drives the scan off the main actor (the tree is large)
/// and publishes results back for SwiftUI.
///
/// Scanning is triggered on the dashboard's first appearance and by a manual
/// "Rescan" — deliberately NOT on the 5-minute usage poller, since logs change
/// slowly and re-reading ~1 GB every few minutes would be wasteful.
@MainActor
@Observable
final class LogActivityState {
    enum Phase: Equatable {
        case idle
        case scanning
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var result: LogScanResult = .empty
    private(set) var costs: [ProviderCost] = []
    private(set) var insights: ActivityInsights = .empty
    private(set) var lastScanned: Date?

    @ObservationIgnored private let scanner = LocalLogScanner()
    @ObservationIgnored private let catalog = ModelPriceCatalog()
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    /// Scan once if nothing has been loaded yet — for the dashboard's `.task`.
    func refreshIfNeeded() {
        guard phase == .idle else { return }
        refresh()
    }

    /// Run a scan + cost pass. Coalesces: a scan already in flight is not restarted.
    func refresh() {
        guard scanTask == nil else { return }
        phase = .scanning
        scanTask = Task { [weak self] in
            guard let self else { return }
            let scan = await scanner.scan()
            await catalog.refreshIfNeeded()
            let costs = await CostEngine.costs(for: scan, using: catalog)
            self.result = scan
            self.costs = costs
            self.insights = InsightsEngine.insights(from: scan)
            self.lastScanned = .now
            self.phase = .loaded
            self.scanTask = nil
        }
    }

    #if DEBUG
        /// Inject a fixed result for SwiftUI Previews (bypasses the scanner).
        static func preview(result: LogScanResult, costs: [ProviderCost]) -> LogActivityState {
            let state = LogActivityState()
            state.result = result
            state.costs = costs
            state.insights = InsightsEngine.insights(from: result)
            state.phase = .loaded
            state.lastScanned = .now
            return state
        }
    #endif
}
